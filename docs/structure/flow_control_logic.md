# Flow Control Logic(FCL)

## gen2 구현

`gen2/src/RTL/flow_control_logic.sv`는 아래 원형의 FCL/FDU 구성을 사용하되,
실제 명령 유입 추적, 순서대로 반환하는 제어, 다중 채널 handshake를 추가한 구현이다.
원형 코드는 `structure_src`에 보존한다. 이 절 이후의 기존 설계 설명과 차이가 있으면
`gen2`에서는 이 절과 RTL의 포트 정의를 따른다.

- FDU는 `STRUCT_FLOW_WINDOWS`개이며, 각 윈도우에 최대
  `STRUCT_FLOW_PC_MAX_RANGE`개의 명령을 수락한다. PC 간격은 `IS_INST_PC_STEP`이다.
- NEL은 Stage 1에서 소비한 IM 응답(`recv_valid`)과 실제 저장한 명령(`recv_keep`)을 구분한다.
  Stage 1 → Stage 2에서 모든 유효 명령의 `{Flow, PC}`를 한 번씩 보고한다.
  목적지가 없거나 x0인 명령도 이 보고와 실행 완료 보고에 포함된다.
- FDU는 PC 위치별 유입/완료 비트맵을 사용한다. 중복 완료 알림은 완료 개수를 늘리지 않는다.
  윈도우가 닫히고 수락한 명령이 모두 완료돼야 반환 가능 상태가 된다.
- 윈도우 번호는 원형 순서로 할당하고, 가장 오래된 윈도우부터 반환한다.
  뒤 윈도우가 먼저 완료돼도 앞 윈도우의 반환을 추월하지 않는다.
- 윈도우별 반환 번호는 공용 `fifo_multichan`에 보관한다. 반환 권한을 가진 FDU만 pop하며,
  입력 파이프라인을 포함한 모든 반환 번호가 빠진 뒤에만 윈도우 번호를 재사용한다.

### IM 요청과 분기 처리

한 번에 최대 `STRUCT_DECODE_NEW_INST`개의 PC를 요청한다. 각 요청은
`valid && get`에서 개별 수락되며, 수락되지 않은 lane의 valid와 `{Flow, PC}`는 유지된다.
윈도우 끝에 남은 명령 수가 적으면 일부 lane만 유효하다.

scheduler 외부 포트는 `o_im_req_pc_valid`, `i_im_req_pc_get`, `o_im_req_pc`이며,
각 lane의 데이터는 MSB부터 `{Flow, PC}`입니다. IM 응답은 `i_im_recv_inst_valid`,
`o_im_recv_inst_get`, `i_im_recv_pc` 및 해당 명령의 디코드 정보로 NEL에 전달합니다.
요청과 응답 모두 lane별 `Valid && Get`에서 전송됩니다.

현재 구현은 **한 요청 묶음만 진행 중일 수 있으며 분기 예측을 하지 않는다.**
IM은 수락한 요청마다 응답해야 하고, 응답은 프로그램 순서를 유지해야 한다.
여러 응답을 한 사이클에 내보낼 때도 낮은 lane부터 프로그램 순서여야 한다.
응답을 여러 사이클로 나누는 것은 허용한다.

NEL은 첫 점프/분기 명령까지 저장하고, 같은 묶음의 뒤쪽 응답은 Get으로 소비하되 저장하지 않는다.
FCL의 `o_nel_discard`는 나중에 도착하는 뒤쪽 응답도 버리게 한다.
모든 요청의 응답을 소비하고 저장한 명령의 rename이 끝난 뒤 다음 묶음을 요청한다.
직접 점프는 NEL의 목표 PC를 사용하고, 조건 분기와 레지스터 점프는 EX 결과를 기다린다.

### gen2 인터페이스 변경

| 경로 | 데이터 및 의미 |
|---|---|
| FCL → IM | lane별 `{Flow, PC}`. Flow 폭은 윈도우 1개 구성에서도 최소 1비트 |
| NEL → FCL | `new_inst_valid/new_inst_pc`: 모든 명령의 rename 완료 이벤트 |
| NEL → FCL | `recv_valid/recv_keep/recv_control`: 응답 소비, Stage 1 저장, 제어 명령 감지 |
| NEL → FCL | `jumpbranch_pc`: 제어 명령 자신의 `{Flow, PC}` |
| NEL → FCL | `jumpbranch_data`: `{target_pc, branch, jump_reg, jump}` |
| EX → WBC → FCL | `branch_data`: **`{resolved_next_pc, Flow, instruction_pc}`** |
| WBC → FCL | `done_pc_data`: 완료한 명령의 `{Flow, PC}` |
| NEL → FCL | `retired_phyreg_data`: `{old_phyreg, Flow, PC}` |
| FCL → PRM | 반환할 물리 레지스터 번호. 0번은 반환하지 않음 |

외부 EX는 조건 분기의 taken/not-taken 모두에 대해 실제 다음 PC를 계산하여
`i_wbc_result_branch_valid/data`로 보고해야 한다. 분기 결과 보고와 별개로
해당 명령의 일반 `i_wbc_result_valid/data` 완료 보고도 필요하다.
FCL은 분기 결과의 `{Flow, instruction_pc}`가 기다리는 명령과 일치할 때만 재개한다.

일반 완료 데이터는 MSB부터 `{RD, Flow, instruction_pc}`이고,
별도 분기 결과는 `{resolved_next_pc, Flow, instruction_pc}`입니다.
조건 분기가 성립하지 않아도 순차 실행 주소를 실제 다음 PC로 보고하므로 Branch Active는 사용하지 않습니다.
이 포맷은 [전체 EX 규약](Top.md#ex-연결을-위한-규칙)과 [WBC](write_back_concatenation.md)에도 동일하게 적용합니다.

`tb_flow_control_logic.sv`는 순서대로 반환, 부분 요청 수락, 중복 완료, 분기 결과 식별을 검사한다.
`tb_scheduler_flow.sv`는 실제 NEL/IST/PRM/RS/WBC/FCL을 연결해 뒤쪽 응답 폐기와
반복적인 RAW 의존성 및 물리 레지스터 재사용을 검사한다.

## 기존 구조 설명 (structure_src)

Flow Control Logic은  
명령의 흐름을 결정하기 위해 PC의 변화를 제어하고  
덮어 씌워져 더이상 사용되지 않는 내부 레지스터 번호를 반환하는 모듈입니다.  

![FCL 다이어그램](../img/8_FCL.JPG)

## 내부의 구성과 역할
### Flow Detect Unit(FDU)
명령 윈도우를 추적하고, 완료되면 더이상 사용되지 않는 내부 레지스터 번호를 반환하는 모듈이며,  
내부에 윈도우 범위 비교기와 FIFO를 가지고 있습니다.  
FCL 내부에 STRUCT_FLOW_WINDOWS 만큼 FDU가 있습니다.  

명령 윈도우를 추적하기 위해 시작 PC, 종료 PC, 실행된 명령의 수, 명령 윈도우가 가지는 명령의 갯수를 저장합니다.  
외부에서 종료 PC를 조작하여 명령 윈도우의 총 명령의 갯수를 업데이트하고,  
입력받은 완료된 명령의 PC가 명령 윈도우 내에 해당하는 명령인지 확인하고, 이에 따라 실행된 명령의 수를 업데이트 합니다.

### Calculate Next Program Counter
Program Counter를 조건에 따라 변경하고, 명령 윈도우를 생성하고 크기를 조정하는 로직입니다.  

조건에 따라 PC를 업데이트 하는 방법이 달라집니다.  
- *점프/분기 조건이 입력되지 않은 경우* <u>다음 명령의 PC로: 현재 명령 윈도우의 Flow Index와 현재 PC+```IS_INST_PC_STEP```를 전달</u>합니다.
    - 단, 명령 윈도우의 상한(```STRUCT_FLOW_PC_MAX_RANGE```)까지 사용된 경우 명령 윈도우는 새롭게 설정되고, 새롭게 설정된 Flow Index를 전달합니다.
- *명령을 통해 즉시 점프가 가능한 명령이 입력된 경우* <u>다음 명령의 PC로: 새로운 명령 윈도우의 Flow Index와 점프되는 PC를 전달</u>합니다. 이때 기존 명령 윈도우는 이전 명령까지 적용되도록 축소합니다.
- *레지스터 기반의 점프/분기 명령이 입력된 경우* <u>다음 명령의 PC로: 해당 명령이 완료되어 새로운 PC가 결정될 때까지 대기</u>합니다. 이때 기존 명령 윈도우는 이전 명령까지 적용되도록 축소합니다.

## 수신/송신하는 정보
### 다음 명령의 PC를 전달
#### 새로운 PC를 IM으로 전달
새로운 명령을 받기 위해 Instruction Memory(외부)에 새로운 명령의 Program Counter를 내보냅니다.

Calculate Next Program Counter에서 생성된 새로운 명령을 전달합니다.  
PC는 하나만 전달되며, Instruction Memory는 전달된 PC를 시작으로 연달아 연결된 STRUCT_DECODE_NEW_INST개의 명령을 NEL로 전달해야 합니다.

**Valid 기반 전송**을 사용합니다.  
배포용 소스 코드에서 명칭은 ```i/o_im_pc_*``` 입니다.

### 점프/분기 명령 여부 수신
#### PC제어 명령의 정보를 NEL에서 수신
Program Counter를 변경하는 명령정보를 받고, 해당 명령의 종류에 따라 특정한 동작이 되도록  
점프/분기/변경될 PC를 입력받습니다.  
(Calculate Next Program Counter를 제어)

**Valid 기반 전송**을 사용하는데, 다른 규격과 달리 주소와 플래그가 수신됩니다.  
- jump[0]: Immediate 값을 이용한 점프 명령 여부
- jump_reg[0]: 레지스터 값을 이용한 점프 명령 여부
- branch[0]: 분기 명령 여부
- new_pc[```IS_INST_BITWIDTH```-1:0]: 점프/분기로 변경되거나 변경될 수 있는 PC. *단, jump_reg 발생에서는 사용하지 않음*
딱 한세트만 전달되며,  
배포용 소스 코드에서 명칭은 ```i/o_nel_jump_branch_*``` 입니다.

### 완료된 명령들의 PC를 수신
#### 실행이 완료된 명령들의 Flow Index와 Program Counter를 WBC에서 수신
명령 윈도우의 관리를 위해 실행이 완료된 명령의 Flow Index와 Program Counter를 입력받습니다.  

실행이 완료된 명령 정보의 데이터 구조는 MSB부터 LSB 순서로 아래와 같고,
|Program Counter|Flow Index|
|-|-|
|[```_BITWIDTH_STRUCT_FLOW_WINDOWS```-1:0]|[```IS_INST_PC_BITWIDTH```-1:0]|

이 정보는 동시에 _STRUCT_EX_OUT_RESULT_ALL 만큼 수신할 수 있습니다.  
단, **첫번째 요소는 항상 분기 명령에 대한 요소**입니다.

**Valid 기반 전송**을 사용합니다.  
배포용 소스 코드에서 명칭은 ```i/o_wbc_pc_*``` 입니다.

#### 처리가 완료된 Branch 결과를 WBC에서 수신
Branch EX에서 출력된 결과를 FCL로 내보냅니다.  

데이터 구조는 MSB부터 LSB 순서로 아래와 같고,
|New Program Counter|Branch Active|
|-|-|
|[```IS_INST_PC_BITWIDTH```-1:0]|[0]|

이 정보는 **오직 하나입니다.**  

**Valid 기반 전송**을 사용합니다.  
배포용 소스 코드에서 명칭은 ```i/o_wbc_branch_*``` 입니다.  

### 덮어 씌워지는 내부 레지스터 번호를 수신
#### 특정 명령 이후에 사용되지 않는 내부 레지스터 번호를 NEL에서 수신
추후 명령 윈도우가 모두 처리되었을때 사용되지 않는 내부 레지스터 반환을 위해  
덮어 씌워지는 내부 레지스터 번호를 입력받습니다.

데이터 구조는 MSB부터 LSB 순서로 아래와 같고,
|Retired Physical Register Number|
|-|
|[```_BITWIDTH_STRUCT_PHYREGS```-1:0]|

이 정보는 동시에 STRUCT_DECODE_NEW_INST 만큼 수신할 수 있습니다.  

**Valid 기반 전송**을 사용합니다.  
배포용 소스 코드에서 명칭은 ```i/o_nel_unallo_reg_*``` 입니다.

### 사용 완료된 내부 레지스터 번호를 반환
#### 반환할 내부 레지스터 번호를 PRM에 전달
#### 반환되는 내부 레지스터 번호를 FCL에서 수신
더이상 사용되지 않는 내부 레지스터 번호를 내보냅니다.

데이터는 내부 레지스터 번호이며,  
이 정보는 동시에 STRUCT_UNALLOCATE_PHYREG 만큼 전달할 수 있습니다.  

**Valid 기반 전송**을 사용합니다.  
배포용 소스 코드에서 명칭은 ```i/o_prm_unallocate_*``` 입니다.
