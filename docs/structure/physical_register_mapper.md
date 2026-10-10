# Physical Register Mapper(PRM)
Physical Register Mapper는  
내부 레지스터 번호를 할당하고, 내부 레지스터에 연결된 명령 대기열을 관리하는 모듈입니다.

![PRM 다이어그램](../img/7_PRM.JPG)

## 내부의 구성과 역할
### Internal(Physical) Register Number Allocator
내부 레지스터를 명령에 사용할 수 있도록 할당하기 위한 내부 레지스터 번호 Allocator입니다.  

이 Allocator는 내부 레지스터 번호를 출력하고, 더이상 사용되지 않는 내부 레지스터 번호를 입력받습니다.  
내부 레지스터의 출력으로 ```_BITWIDTH_STRUCT_PHYREGS```만큼의 너비를 가지고,  
이 정보는 동시에 STRUCT_DECODE_NEW_INST만큼 할당하고, STRUCT_UNALLOCATE_PHYREG만큼 반환 할 수 있습니다.

### Internal Register <-> IST Entry Map Buffer Count Table
내부 레지스터 번호에 대기중인 명령의 갯수를 저장하는 Register File입니다.
Register File의 주소로 **내부 레지스터 번호**(너비: ```_BITWIDTH_STRUCT_PHYREGS```)를 사용하고,   
Register File의 데이터로 **대기열에 저장된 명령의 수**(너비: ```_BITWIDTH_STRUCT_PRM_ENTRY_BUFFER```)를 저장합니다.  

이 Register File 입출력 채널 구성으로
- 입력 채널 갯수: ```STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS```
    - 아래부터 IST 모듈에서 입력된 순서로 전달하여   
    *Operand에 사용된 내부 레지스터 주소를 입력된 명령과 Operand 순서로 묶인* 형태의 주소를 사용하고,  
    동일한 순서로 **업데이트 되는 명령의 Operand 위치**(Write Enable)와 **업데이트 이후 카운터 값을 데이터로 입력**합니다.
- 출력 채널 갯수: ```(STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS)+_STRUCT_EX_OUT_RESULT_ALL```
    - <u>내부 레지스터 번호</u>를  
    IST의 Operand 묶음의 명령들, EX의 번호 순서대로 전달받아 주소를 사용하고,  
    동일한 순서로 **저장된 카운터 값이 데이터로 출력**됩니다. 

### Internal Register <-> IST Entry Map Buffer
여러개가 배치되어 결과를 대기하는 내부 레지스터에 할당된 명령을 저장하는 대기열입니다.  
총 ```STRUCT_PRM_ENTRY_BUFFER```개의 Internal Register <-> IST Entry Map Buffer가 배치됩니다.  
Register File의 주소로 **내부 레지스터 번호**(너비: ```_BITWIDTH_STRUCT_PHYREGS```)를 사용하고,   
Register File의 데이터로 **Instruction State Entry 번호**(너비: ```_BITWIDTH_STRUCT_INST_STATE_ENTRIES```)를 저장합니다.  

이 Register File 입출력 채널 구성으로
- 입력 채널 갯수: ```STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS```
    - 아래부터 IST 모듈에서 입력된 순서로 전달하여   
    *Operand에 사용된 내부 레지스터 주소를 입력된 명령과 Operand 순서로 묶인* 형태의 주소를 사용하고,  
    동일한 순서로 **카운터로 추출된 업데이트 되는 위치와**(Write Enable)와 **Instruction State Entry 번호를 데이터로 입력**합니다.
- 출력 채널 갯수: ```_STRUCT_EX_OUT_RESULT_ALL```
    - <u>내부 레지스터 번호</u>를  
    EX의 번호 순서대로 전달받아 주소를 사용하고,  
    동일한 순서로 **Instruction State Entry 번호가 데이터로 출력**됩니다. 

### Buffer Position Creator
내부 레지스터에 대한 카운터를 업데이트 하고, 대기열의 위치를 지정하기 위한 로직입니다.  
내부 레지스터 번호에 대한 Bitmap/Suffix OR/Prefix Sum 회로를 이용하여 입력에서 내부 레지스터가 겹치는 경우를 확인하고, Internal Register <-> IST Entry Map Buffer Count Table의 출력을 이용하여 새로운 카운터 값을 결정하는 구조를 가집니다.  

### Output FIFO
대기열에 저장된 IST 엔트리 번호가 전달되는 FIFO 입니다.  
가변 입출력 FIFO를 사용합니다.  

이 FIFO 입출력 채널 구성으로(가변 입출력이므로, 최대를 서술합니다.)
- 최대 입력 채널 갯수: ```STRUCT_PRM_ENTRY_BUFFER```
    - 위치와 상관 없이 데이터가 전달될 수 있고, 유효한 데이터는 Valid와 함께 전달합니다.
- 최대 출력 채널 갯수: ```STRUCT_PRM_ENTRY_UPDATE```
    - 입력되는 유효한 데이터들이 LSB부터 모아져 정렬되며, Valid 필드는 유효한 데이터 입력 갯수만큼 LSB부터 연달아 출력됩니다.  

## 수신/송신하는 정보
### 새로운 레지스터를 할당하고 반환
#### 할당 가능한 내부 레지스터 번호를 NEL로 전달
할당 가능한 내부 레지스터 번호를 출력합니다. Output FIFO의 출력입니다.

데이터는 내부 레지스터 번호이며,  
이 정보는 동시에 STRUCT_DECODE_NEW_INST 만큼 전달할 수 있습니다.  

**Handshake 기반 전송**을 사용합니다.  
가져가기 신호(Get)이 우선 발생하는 다른 Handshake 기반 전송과는 다르게  
**데이터 유효성 신호(Valid)**가 먼저 발생해야 하는 전송구조입니다.  
gen2에서는 할당 가능한 레지스터가 존재하고 PRM 입력 처리가 정체되지 않은 경우 Valid를 출력합니다.
대기열 용량을 초과하는 IST 입력 묶음은 원본 Valid/Data 형태로 보관하고, 묶음 전체를 처리할 수 있을 때까지 기다립니다.
이때 `input_stall`로 모든 할당 Valid를 내려 NEL의 새 명령 유입과 rename 진행을 멈춥니다.
목적지 레지스터가 없거나 x0에 쓰는 명령도 이 정지 조건을 따릅니다. 이미 rename된 NEL Stage 2의 후속 입력은 PRM 버퍼가 수용합니다.
따라서 Valid는 물리 레지스터 재고뿐 아니라 PRM의 진행 허가도 뜻합니다.
gen2 포트 명칭은 `o_nel_phyreg_valid/data`, `i_nel_phyreg_get`입니다.

#### 반환되는 내부 레지스터 번호를 FCL에서 수신
더이상 사용되지 않는 내부 레지스터 번호를 입력받습니다.

데이터는 내부 레지스터 번호이며,  
이 정보는 동시에 STRUCT_UNALLOCATE_PHYREG 만큼 수신할 수 있습니다.  

**Valid 기반 전송**을 사용합니다.  
배포용 소스 코드에서 명칭은 ```i/o_fcl_unallocate_*``` 입니다.

### 내부 레지스터 번호에 연결된 명령 대기열에 레지스터를 추가
#### 대기열에 추가할 IST 번호를 IST에서 수신
아직 준비되지 않은 내부 레지스터를 소스로 사용하여 대기열에 추가해야 하는 명령의 IST 엔트리 번호를 입력받습니다.

데이터는 `{IST 엔트리 번호, 물리 레지스터 번호}`이며(MSB → LSB),
이 정보는 동시에 STRUCT_DECODE_NEW_INST*IS_INST_OPERANDS 만큼 수신할 수 있습니다.  

**Valid 기반 전송**을 사용합니다.  
gen2 포트 명칭은 `i_ist_wait_phyreg_valid/data`입니다. Get이나 재전송은 없으며, IST가 수락한 명령의 미완료 소스마다 한 번 전달합니다.

### 완료된 내부 레지스터 번호에 연결된 대기열의 명령들을 전달
#### 처리가 완료된 내부 레지스터 번호를 WBC에서 수신
준비된 내부 레지스터 번호를 WBC에서 입력받습니다.  

데이터는 내부 레지스터 번호이며,  
이 정보는 동시에 _STRUCT_EX_OUT_RESULT_ALL 만큼 수신할 수 있습니다. 

**Valid 기반 전송**을 사용합니다.  
배포용 소스 코드에서 명칭은 ```i/o_wbc_phyreg_*``` 입니다.

#### 준비된 내부 레지스터의 대기열에 저장된 IST 엔트리 번호를 IST로 전달
Internal Register <-> IST Entry Map Buffer에서 가져온 내부 레지스터 대기열의 IST 엔트리 번호들을 내보냅니다.

데이터는 `{IST 엔트리 번호, 물리 레지스터 번호}`이며(MSB → LSB),
이 정보는 동시에 STRUCT_PRM_ENTRY_UPDATE 만큼 전송할 수 있습니다. 

**Valid 기반 전송**을 사용합니다. Get 포트는 없습니다.
IST는 RS의 수신 가능 여부와 무관하게 통지를 처리하고, 실행 가능한 엔트리를 pending 상태로 보관합니다.
PRM은 출력된 통지를 해당 사이클에 소비된 것으로 처리하므로 IST가 통지를 거부하거나 재전송을 요구할 수 없습니다.
gen2 포트 명칭은 `o_ist_ready_phyreg_valid/data`입니다.
