# Ready Station(RS)
Ready Station은  
준비된 명령이 EX에서 처리되도록  
내부 명령이 대기하는 모듈입니다.  

![RS 다이어그램](../img/5_RS.JPG)

## 내부의 구성과 역할
### EX Path Position Splitter
EX Path와 맞는 FIFO에 내부 명령을 전달하기 위한 Position Spliter 입니다.  
내부적으로 **EX Path**로 할당된 Position Spliter가 있고, 입력에서 명령의 **EX Path** 필드와 비교하여  
내부의 Position Spliter 번호와 동일한 경우 입력이 유효하도록 로직이 구성되어 있습니다.  
(EX Path 번호와 내부의 Position Spliter 번호가 동일해야 내부의 Position Spliter의 Valid가 발생하도록 설계됩니다)
Position Spliter의 특징에 따라 LSB 쪽으로 데이터가 정렬됩니다.  

입력으로   
|Program Counter|Flow Index|EX Path|Micro-Opcode|Immediate Value|RD Address|...RS(1~n) Addresses List...|
|-|-|-|-|-|-|-|

를 데이터 구조로 사용하며, 동시에 STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE 만큼 입력받을 수 있습니다.  

출력으로  
|Program Counter|Flow Index|EX Path|Micro-Opcode|Immediate Value|RD Address|...RS(1~n) Addresses List...|
|-|-|-|-|-|-|-|

를 데이터 구조로 사용하며, EX Path를 포함한 입력 패킷을 그대로 전달합니다. 동시에 STRUCT_RS_OUT_ENTRY[EX Path] 만큼 출력할 수 있습니다.
EX Path는 개념적인 Micro-Op의 일부이고, RTL에서는 분류 편의를 위해 별도 필드로 표현합니다. 소스 레지스터 값은 이 인터페이스에 포함되지 않습니다.

### EX Path FIFO
특정한 EX Path로 향하는 명령이 버퍼링 되는 FIFO 입니다.  
가변 입출력 FIFO를 사용하며,  
FIFO의 데이터는 (LSB에서 MSB로)  
|Program Counter|Flow Index|EX Path|Micro-Opcode|Immediate Value|RD Address|...RS(1~n) Addresses List...|
|-|-|-|-|-|-|-|

입니다.

이 FIFO 입출력 채널 구성으로(가변 입출력이므로, 최대를 서술합니다.)
- 최대 입력 채널 갯수: ```STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE```
    - 위치와 상관 없이 데이터가 전달될 수 있고, 유효한 데이터는 Valid와 함께 전달합니다.
- 최대 출력 채널 갯수: ```STRUCT_RS_OUT_ENTRY[FIFO의 EX_PATH]```
    - 입력되는 유효한 데이터들이 LSB부터 모아져 정렬되며, Valid 필드는 유효한 데이터 입력 갯수만큼 LSB부터 연달아 출력됩니다.  

## 수신/송신하는 정보
### 준비가 완료된 명령을 실행하도록 버퍼링
RS는 준비가 완료된 명령을 IST에서 받고 FIFO에 저장하며, FIFO의 출력을 EX로 전달합니다.  

#### 준비가 완료된 명령을 IST에서 수신
준비된 명령을 IST에서 입력받습니다.  

데이터 구조는 MSB부터 LSB 순서로 아래와 같고,
|...RS(n~1) Addresses List...|RD Address|Imm Value|Micro-Op|EX Path|Flow Index|Program Counter|
|-|-|-|-|-|-|-|
|[```(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)```-1:0]|[```_BITWIDTH_STRUCT_PHYREGS```-1:0]|[```IS_INST_IMM```-1:0]|[```EX_INST_MICROOP_BITWIDTH```-1:0]|[```_BITWIDTH_STRUCT_EX_PATH```-1:0]|[```_BITWIDTH_STRUCT_FLOW_WINDOWS```-1:0]|[```IS_INST_PC_BITWIDTH```-1:0]|

이 정보는 동시에 STRUCT_DECODE_NEW_INST+STRUCT_PRM_ENTRY_UPDATE 만큼 수신할 수 있습니다.  

**Handshake 기반 전송**을 사용합니다. 
gen2에서는 각 FIFO의 입력 정렬 공간까지 고려한 `o_push_ready`를 사용하며, 모든 EX Path가 입력 묶음을 받을 수 있을 때 Get을 출력합니다. Get은 IST의 Valid와 무관하게 계산합니다.
배포용 소스 코드에서 명칭은 ```i/o_ist_readyinst_*``` 입니다.

#### 준비가 완료된 명령을 EX에 전달
준비된 명령을 EX로 내보냅니다.  
순서는 EX Path가 낮은 순부터 높은 순으로 전달되며,  
특히 EX Path의 번호에 맞게 STRUCT_RS_OUT_ENTRY[EX Path 번호] 필드를 사용하고,  
사용되지 않는 영역은 비워두어야 합니다.  
(STRUCT_RS_OUT_ENTRY[EX Path 번호]만큼 그대로 EX의 입력에 할당됩니다. 절대 모으지거나 위치를 변경하지 않습니다.)

데이터 구조는 MSB부터 LSB 순서로 아래와 같고,
|...RS(n~1) Addresses List...|RD Address|Imm Value|Micro-Op|EX Path|Flow Index|Program Counter|
|-|-|-|-|-|-|-|
|[```(_BITWIDTH_STRUCT_PHYREGS*IS_INST_OPERANDS)```-1:0]|[```_BITWIDTH_STRUCT_PHYREGS```-1:0]|[```IS_INST_IMM```-1:0]|[```EX_INST_MICROOP_BITWIDTH```-1:0]|[```_BITWIDTH_STRUCT_EX_PATH```-1:0]|[```_BITWIDTH_STRUCT_FLOW_WINDOWS```-1:0]|[```IS_INST_PC_BITWIDTH```-1:0]|

이 정보는 동시에 STRUCT_RS_OUT_ENTRY[EX Path 번호]의 총합 만큼 전달할 수 있습니다.  

**Handshake 기반 전송**을 사용합니다. 
FIFO 출력 데이터의 유효성이 Valid이고, Get은 EX에서 입력받습니다. `Valid && Get`일 때만 해당 채널이 전송됩니다.
배포용 소스 코드에서 명칭은 ```i/o_ex_exeinst_*``` 입니다.
