# Instruction State Table(IST)
Instruction State Table은  
입력된 명령에서, 준비된 명령은 처리할 수 있도록 전달하고,  
아직 준비되지 않은 명령은 대기하는 모듈입니다.

![IST 다이어그램](../img/4_IST.JPG)

## 내부의 구성과 역할
### 구조 파라미터와 엔트리 할당
gen2는 PRM 통지 폭과 저장 명령 발행 폭을 분리합니다.

| 파라미터 | 역할 | 기본값 |
|---|---|---|
| `STRUCT_DECODE_NEW_INST` | NEL 입력 폭, 최대 동시 SRAM 쓰기 수 | 2 |
| `STRUCT_PRM_ENTRY_UPDATE` | PRM 완료 통지 처리 폭 | 5 |
| `STRUCT_IST_ISSUE_WIDTH` | 저장된 명령의 RS 전달 폭 | `STRUCT_EX_CORES` |
| `STRUCT_IST_BANKS` | 독립 1R1W 명령 SRAM 뱅크 수 | `max(decode, issue)` 이상의 최소 2의 거듭제곱 |

예를 들어 4-decode / 7-issue는 기본 8뱅크를 사용합니다. 기본값은 코어당 한 명령 수락을 가정하며, 다른 수락 폭은 `STRUCT_IST_ISSUE_WIDTH`로 지정합니다.
뱅크 수는 2의 거듭제곱이고 decode 폭 이상이어야 합니다. issue 폭보다 적은 뱅크도 지정할 수 있으나 지속 읽기 처리량이 제한됩니다.
엔트리 수는 decode 폭 이상이어야 합니다. 뱅크 수로 나누어떨어지지 않는 엔트리 수는 마지막 행의 범위 밖 주소를 할당 대상에서 제외합니다.

공용 free-entry FIFO 대신 `active_entries`에서 뱅크별 빈 행을 찾습니다.
한 입력 묶음에는 서로 다른 뱅크를 할당하여 쓰기 충돌을 방지합니다. 빈 행이 많은 뱅크를 우선하며, 동률이면 회전하는 뱅크 우선순위를 사용합니다.
번호의 하위 `$clog2(STRUCT_IST_BANKS)`비트는 뱅크, 나머지는 행 주소입니다. 1뱅크에서는 번호 전체가 행 주소입니다.
번호 반환은 RS가 해당 명령을 수락할 때 active 비트를 지우는 방식이며, 다음 사이클부터 재할당할 수 있습니다.
NEL 수락은 전체 decode 폭의 서로 다른 빈 뱅크를 확보하는 보수적인 묶음 규약을 유지합니다. 따라서 빈 엔트리가 특정 뱅크에 몰리면 전체 빈 개수가 충분해도 일시 정지할 수 있습니다.

### Instruction Entry Table
명령 본문은 `STRUCT_IST_BANKS`개의 `bram_custom`에 분산 저장합니다.
각 뱅크는 독립 쓰기 포트 하나와 동기식 읽기 포트 하나를 가지며, 깊이는 `ceil(STRUCT_INST_STATE_ENTRIES / STRUCT_IST_BANKS)`입니다.
본문 폭은 `_BITWIDTH_EX_INST_WIDTH`이고, 새 명령의 operand-ready 비트는 본문에 포함하지 않습니다.

| ...RS(n~1) Addresses List... | RD Address | Imm Value | Micro-Op | EX Path | Flow Index | Program Counter |
|---|---|---|---|---|---|---|
| `PHYREG_BITS * IS_INST_OPERANDS` | `PHYREG_BITS` | `IS_INST_IMM` | `EX_INST_MICROOP_BITWIDTH` | `EX_PATH_BITS` | `FLOW_BITS` | `IS_INST_PC_BITWIDTH` |

명령 SRAM은 reset하지 않습니다. reset은 active/pending/queued와 요청·응답·출력 valid를 지워 이전 데이터를 무효화합니다.
동시에 읽고 쓰는 유효 엔트리는 서로 다릅니다. 이미 준비된 새 명령은 기존 bypass 레지스터로 전달하여 SRAM을 사용하지 않습니다.
`bram_custom`은 RTL 시뮬레이션 및 RAM 추론 경계이며, ASIC에서는 목표 공정의 SRAM 매크로 어댑터로 교체해야 합니다.

### 주소 FIFO와 동기식 읽기
뱅크마다 깊이 2의 주소 FIFO를 둡니다. FIFO에는 명령 본문 대신 행 주소만 저장하며 뱅크 번호는 연결로 결정됩니다.
각 뱅크는 pending 중 하나를 round-robin으로 골라 사이클당 최대 한 주소를 예약합니다.
FIFO가 가득 차도 PRM 통지는 pending에 남습니다. `queued_entries`는 예약부터 RS 수락까지 유지하여 중복 완료 통지에 의한 재예약을 막습니다.

FIFO의 주소는 뱅크 응답 공간이 있을 때 SRAM에 제출합니다. 읽기 응답이 정지하면 행 주소를 유지하며 엔트리도 반환하지 않습니다.
뱅크 응답은 round-robin으로 빈 발행 lane에 옮깁니다. lane마다 본문과 IST 번호를 보관하므로 일부 lane만 수락해도 나머지 출력은 안정적으로 유지됩니다.

정체가 없을 때 PRM 완료를 받은 에지를 T0라 하면, T1 주소 FIFO 등록, T2 SRAM 읽기 응답, T3 발행 레지스터 등록, T4 RS 수락 순서입니다.
각 단계는 서로 다른 명령을 병렬로 처리합니다. 뱅크당 최대 한 읽기/사이클, 저장 명령 출력은 최대 `STRUCT_IST_ISSUE_WIDTH`개/사이클입니다. 뱅크 충돌과 출력 정체 시 대기 시간이 추가됩니다.

### Instruction Source Table
대기하는 명령에서 소스로 사용하는 내부 레지스터 번호를 저장하는 Register File입니다.  
Register File의 주소로 **Instruction State Entry 번호**(너비: ```_BITWIDTH_STRUCT_INST_STATE_ENTRIES```)를 사용하고,   
Register File의 데이터로 **소스로 사용되는 내부 레지스터 번호**(너비: ```_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS```)를 저장합니다.  
 
이 Register File 입출력 채널 구성으로
- 입력 채널 갯수: ```STRUCT_DECODE_NEW_INST```
    - 아래부터 IST 모듈에 입력된 순서로 전달하여   
    *Instruction State Entry Number Allocator의 낮은 할당 필드 부터 높은 할당 필드에 출력된 Entry Number* 형태의 주소를 사용하고,  
    동일한 순서로 **입력되는 명령의 위치**(Write Enable)와 **입력되는 내부 명령을 데이터로 입력**합니다.
- 출력 채널 갯수: ```STRUCT_PRM_ENTRY_UPDATE```
    - <u>IST 엔트리 번호</u>를  
    RPM에서 수신된 필드 순서로 전달하여  
    *[IST Entry 1], ... , [IST Entry n]*  
    형태의 주소를 사용하고,  
    동일한 순서로 **저장된 내부 명령의 소스 레지스터 번호들이 데이터로 출력**됩니다.  

### Ready Flags Table
대기하는 명령에서 준비된 내부 레지스터의 Ready Flag를 저장하는 Register File입니다.  
Register File의 주소로 **Instruction State Entry 번호**(너비: ```_BITWIDTH_STRUCT_INST_STATE_ENTRIES```)를 사용하고,   
Register File의 데이터로 **소스 레지스터 준비 상태**(너비: 1)를 저장합니다.  

이 Register File 입출력 채널 구성으로
- 입력 채널 갯수: ```STRUCT_DECODE_NEW_INST```
    - 아래부터 IST 모듈에 입력된 순서로 전달하여   
    *Instruction State Entry Number Allocator의 낮은 할당 필드 부터 높은 할당 필드에 출력된 Entry Number* 형태의 주소를 사용하고,  
    동일한 순서로 **업데이트하는 Ready Flag의 위치**(Write Enable)와 **업데이트하는 Ready Flag를 데이터로 입력**합니다.
- 출력 채널 갯수: ```STRUCT_PRM_ENTRY_UPDATE```
    - <u>IST 엔트리 번호</u>를  
    RPM에서 수신된 필드 순서로 전달하여  
    *[IST Entry 1], ... , [IST Entry n]*  
    형태의 주소를 사용하고,  
    동일한 순서로 **저장된 Ready Flag가 데이터로 출력**됩니다.  

### IST-PHYREG Mapping Information
입력되는 내부 명령 체계에서 소스 레지스터와 현재 IST 엔트리 번호를 그대로 전달하는 로직으로,  
입력되는 내부 명령 체계의 Ready Flag의 반전을 Valid로 적용합니다.  
즉, **Ready Flag가 활성화 되지 않은 경우만 전달하는 구조**입니다.   

### Ready Checker
PRM에서 수신한 IST 엔트리 번호와 내부 레지스터 번호를 이용하여 Ready Flags Table을 업데이트 하고,  
업데이트 하는 IST 엔트리의 모든 Ready Flag가 활성화 되는 경우 해당 엔트리를 pending으로 기록합니다.
등록된 pending은 다음 사이클부터 뱅크별 주소 FIFO에 예약하고, 동기식 SRAM 읽기 및 출력 보관을 거쳐 RS에 제공합니다.
RS가 막혀도 PRM 통지는 계속 수신하며, 같은 엔트리의 여러 소스 완료는 합쳐서 반영합니다.

## 수신/송신하는 정보
### 소스 레지스터 번호를 대기열에 추가하거나, 사용 가능 상태를 수신
IST는 대기가 필요한 내부 레지스터 번호를 IST 엔트리 번호와 함께 전달하거나,  
준비된 내부 레지스터 번호를 IST 엔트리 번호와 함께 수신받아 실행 가능한 명령 상태로 변경합니다.  

#### 대기가 필요한 내부 레지스터 번호를 IST 엔트리 번호와 함께 PRM으로 전달
새로운 명령이 들어오면 내부 레지스터 번호에 해당하는 대기열에 명령의 IST 엔트리 번호를 저장하기 위해  
내부 레지스터 번호와 명령에 할당된 IST 엔트리 번호를 내보냅니다.  
이때, 데이터의 유효성은 명령의 Ready Flag에 따르며, Ready Flag가 활성화 되지 않는 경우에 Valid 신호를 출력합니다.   

데이터 구조는 MSB부터 LSB 순서로 아래와 같고,
|Instruction State Entry Number|Physical Register Number|
|-|-|
|[```_BITWIDTH_STRUCT_INST_STATE_ENTRIES```-1:0]|[```_BITWIDTH_STRUCT_PHYREGS```-1:0]|

이 정보는 동시에 STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS 만큼 전달할 수 있습니다.  

**Valid 기반 전송**을 사용합니다.  
배포용 소스 코드에서 명칭은 ```i/o_prm_wait_phyreg_*``` 입니다.

#### 준비 완료된 내부 레지스터 번호와 IST 엔트리 번호와 함께 PRM에서 수신
준비가 완료된 내부 레지스터가 있다면, PRM에서 내부 레지스터 대기열에 있던 IST 엔트리를 입력받습니다.    

데이터 구조는 MSB부터 LSB 순서로 아래와 같고,
|Instruction State Entry Number|Physical Register Number|
|-|-|
|[```_BITWIDTH_STRUCT_INST_STATE_ENTRIES```-1:0]|[```_BITWIDTH_STRUCT_PHYREGS```-1:0]|

이 정보는 동시에 STRUCT_PRM_ENTRY_UPDATE 만큼 수신할 수 있습니다.  

**Valid 기반 전송**을 사용합니다. Get 포트는 없습니다.
RS가 정지해도 완료 통지를 수신하여 Ready Flag와 pending 상태를 갱신합니다.
gen2 포트 명칭은 `i_prm_ready_phyreg_valid/data`입니다.

### 새로운 내부 명령을 수신하고, 준비된 내부 명령을 전달
#### 새로운 내부 명령을 NEL에서 수신
새로운 명령을 NEL에서 입력받습니다.  
이때 모든 Operand의 Ready Flag가 활성화 되어 있다면 별도의 출력 보관 레지스터에 저장하고, 아니라면 IST 엔트리를 할당하여 저장합니다.
이미 준비된 명령은 수락 다음 사이클부터 RS에 제공하며, IST 엔트리를 사용하지 않습니다.

데이터 구조는 MSB부터 LSB 순서로 아래와 같고,
|...RS Ready List...|...RS(n~1) Addresses List...|RD Address|Imm Value|Micro-Op|EX Path|Flow Index|Program Counter|
|-|-|-|-|-|-|-|-|
|[```IS_INST_OPERANDS```-1:0]|[```(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)```-1:0]|[```_BITWIDTH_STRUCT_PHYREGS```-1:0]|[```IS_INST_IMM```-1:0]|[```EX_INST_MICROOP_BITWIDTH```-1:0]|[```_BITWIDTH_STRUCT_EX_PATH```-1:0]|[```_BITWIDTH_STRUCT_FLOW_WINDOWS```-1:0]|[```IS_INST_PC_BITWIDTH```-1:0]|

이 정보는 동시에 STRUCT_DECODE_NEW_INST 만큼 수신할 수 있습니다.  

**Handshake 기반 전송**을 사용합니다.  
수락 조건은 전체 decode 채널에 서로 다른 뱅크의 빈 엔트리 확보와, 이미 준비된 명령을 보관할 출력 레지스터 공간입니다.
출력 레지스터가 비어 있거나 기존 데이터가 이번 사이클에 모두 전송된다면 새 묶음을 받을 수 있습니다.
RS의 모든 Get이 켜져야 하는 조건은 없습니다. 입력 묶음은 전체 단위로 수락합니다.
NEL은 이 경로에서 모든 Get을 확인한 뒤 Valid를 발생시키는 예외 규약을 유지합니다.
gen2 포트 명칭은 `i_nel_new_inst_valid/data`, `o_nel_new_inst_get`입니다.

#### 준비된 내부 명령을 RS로 전달
준비된 명령을 RS로 내보냅니다.   

데이터 구조는 MSB부터 LSB 순서로 아래와 같고,
|...RS(n~1) Addresses List...|RD Address|Imm Value|Micro-Op|EX Path|Flow Index|Program Counter|
|-|-|-|-|-|-|-|
|[```(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)```-1:0]|[```_BITWIDTH_STRUCT_PHYREGS```-1:0]|[```IS_INST_IMM```-1:0]|[```EX_INST_MICROOP_BITWIDTH```-1:0]|[```_BITWIDTH_STRUCT_EX_PATH```-1:0]|[```_BITWIDTH_STRUCT_FLOW_WINDOWS```-1:0]|[```IS_INST_PC_BITWIDTH```-1:0]|

이 정보는 동시에 STRUCT_DECODE_NEW_INST+STRUCT_IST_ISSUE_WIDTH 만큼 전달할 수 있습니다.

**Handshake 기반 전송**을 사용합니다.  
gen2 포트 명칭은 `o_rs_ready_inst_valid/data`, `i_rs_ready_inst_get`입니다.
Valid는 Get과 무관하게 발생하며, `Valid && Get`인 채널만 전송 완료입니다.
`Valid && !Get`인 채널은 다음 사이클에도 같은 Valid와 Data를 유지합니다.
낮은 `STRUCT_IST_ISSUE_WIDTH`개 채널은 SRAM에서 읽은 저장 명령, 높은 `STRUCT_DECODE_NEW_INST`개 채널은 이미 준비된 새 명령을 전달합니다.
일부 lane만 수락되면 나머지 lane의 Valid/Data는 유지하고, 비거나 수락된 lane은 다음 뱅크 응답으로 채울 수 있습니다.
IST 엔트리는 RS 전송 완료 시에만 해제합니다. 주소 FIFO 등록이나 SRAM 읽기 완료만으로는 재할당하지 않습니다.
