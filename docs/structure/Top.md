# 을숙도 아키텍쳐 쏘아보기
을숙도 아키텍쳐는 
프로세서에서  
여러 명령을 동시에 처리하는 **슈퍼스칼라**와  
순서와 상관없이 실행할 수 있는 명령을 즉시 처리 하는 **비순차적 실행 처리**  
가 적용된 구조를 구현합니다.

## 전체적인 컨셉은요?
프로세서는 명령어를 처리하여 특정한 동작을 진행하는 디지털 회로입니다.  
을숙도 아키텍쳐의 중점은 **명령의 대기, 가용 상태를 확인하고 관리**하는 것입니다.  
이때 데이터 종속성 문제를 해결하기 위해 **레지스터 체계를 바꾸어 다른 이름으로 변경**합니다.  
특히 새롭게 입력되는 명령의 결과 레지스터는 **항상 새로운 레지스터 이름으로 변경**하여  
같은 이름을 가진 레지스터를 수정할 때 발생하는 WAW 해저드 문제를 해결하고자 합니다.

### 어떤 부분을 중점으로 구현하고 있나요?
실질적인 구현을 위해 **내부적인 명령/레지스터 번호를 할당하고 반환하는 구조**를 가집니다.  
명령의 대기, 가용 상태를 확인하고 관리하기 위해,  
명령에서 레지스터 번호를 항상 감시하는 구조를 가지는것이 일반적입니다.  
특히 상용 프로세서에서는 *Contents Addressable Memory(CAM)*이라는 구조를 사용하여  
명령이 저장된 각각의 엔트리에서 필요한 소스 레지스터 만큼 비교기를 사용하고 연결하는 구조를 가져  
Glitch와 Fan-Out 관점에서 불리합니다.  
이런 문제를 완화하고자,  
(내부의 체계로 변환된)레지스터가 필요한 *명령의 번호*를 **레지스터 번호 기준으로 저장**하여  
실행 유닛에서 결과를 만들어낸 레지스터 번호를 전달받아  
저장된 명령의 번호로 명령의 상태를 변경하는 구조로 설계하고 있으며,  
이에 따라 CAM에 비해 상당히 감소된 Fan-Out과 비교기 수를 도출하여  
높은 전력 효율을 기대하고 있습니다.

## 컨셉에 따라 어떻게 동작하나요?
![동작 컨셉 다이어그램](../img/1_Overview.JPG)
을숙도 아키텍쳐는 **명령의 대기, 가용 상태를 확인하고 관리**하기 위해  
프로세서의 스케줄러를 6개의 구획으로 나누었습니다.  
명령의 입력부터 대기, 가용 상태로 변경과 최종 처리 순서를 반영하여 설명하면,
1. 새로운 명령을 입력받아, 이때 명령의 레지스터들을 내부 체계의 이름으로 변경하며,  
새로운 명령에서 필요한 레지스터의 준비여부를 모아 내부에서 처리하는 명령 체계로 변환하는  
[**New Entry Logic(NEL)**](new_entry_logic.md)
2. 내부 체계로 변경된 명령을 저장하고, 필요한 레지스터들의 준비 여부를 업데이트 하며,  
명령의 소스 레지스터들이 모두 준비되면 해당 명령을 외부로 출력하는  
[**Instruction State Table(IST)**](instruction_state_table.md)
3. 내부 체계로 변경된 레지스터 이름을 기준으로,  
특정 레지스터가 사용되는 명령의 내부적인 번호를 저장해두고,  
실행 유닛에서 처리가 완료된 레지스터 번호를 받아 해당 레지스터의 명령 번호를 출력하는  
[**Physical Register Mapper(PRM)**](physical_register_mapper.md)
4. 준비된 명령들이 필요한 실행 유닛에 들어가도록 배치하고,  
각 실행 유닛이 동작할 수 있는 상태에 전달할 수 있도록 버퍼링하는  
[**Ready Station(RS)**](ready_station.md)
5. 실행 유닛에서 완료된 명령의 레지스터 번호를 전달하고,  
명령의 순서를 바꾸는 정보를 전달하거나 외부 I/O로 데이터를 교환하는  
[**Write Back Concatenation(WBC)**](write_back_concatenation.md)
6. 명령의 순서를 전달하고, 분기/점프로 둘러싸인 Basic Block 단위로 순서를 관리하며,   
명령의 처리와 함께 새로운 레지스터로 할당되면서 필요없는 레지스터를 반환하는  
[**Flow Control Logic(FCL)**](flow_control_logic.md)

( "내부적인"과 같은 내용을 서술하지 않은 경우 외부에서 들어온 정보 기준입니다.  
명령:PC / 명령의 내부적인 번호:IST 엔트리 번호 )

전체적으로 할당 가능한 내부 레지스터 번호는 1번부터 시작하며,  
내부 레지스터 0은 항상 "0" 값을 출력하는 구조로 만들어져 있습니다.  
따라서, 내부 레지스터 0은 항상 준비되어 있고, 수정할 수 없는 속성을 가집니다.

## 이 전체 모듈은 어떤 입력을 받고 어떤 출력을 하나요?
필수적인 I/O로,  
**새로운 명령을 입력** 받고  
**필요한 명령의 주소를 출력**하는  
구조를 가집니다.   

해당 프로세서의 성격에 따라, 외부로 전달되는 신호를 커스텀 할 수 있는데,  
대표적으로 메모리 읽기/쓰기와 특정 제어값을 주고받을 수 있습니다.  

## 내부적으로 모듈들은 어떻게 연결되나요?
![모듈간 인터페이스 다이어그램](../img/2_Interfaces.JPG)
각 모듈은 특정한 데이터 구조들을 **Valid 발생 단위**와 **Handshake 기반 전송 단위**로 전달합니다.  

데이터 수신에서,  
Valid 발생 단위의 데이터 전송에서 수신부는 항상 받을 준비가 되어 있어야 합니다.  
Handshake 기반 전송 단위에서 **Ready 필드**를 통해 결정합니다.  
데이터 송신에서,
Valid 발생 단위의 데이터 전송과 Handshake 기반 전송 단위에서 모두  
**유효한 데이터 위치의 Valid 필드**를 통해 결정합니다.  

### Handshake 기반 전송 단위의 구체적인 설명
신호는 다음과 같습니다.  
|Signal Name|Direction|Description|
|-|-|-|
|Valid|Sender->Recevier|데이터의 유효성|
|Data|Sender->Recevier|전송되는 데이터|
|Get|Recevier->Sender|가져가기 신호|

을숙도 구조에서 Handshake 데이터 전달은 가져가기 신호를 가능한 항상 띄웁니다.
Valid와 Get 양쪽의 동일한 비트 위치의 필드가 발생하면 **데이터 전송완료**입니다.

간단한 예시를 보이면  
(가져기기 신호가 항상 발생중인 경우)
1. 수신하는 부분에서 Get 신호는 내부 모듈이 수신 불가능한 경우를 제외하고 항상 발생합니다.
2. 이때 전송하는 부분에서 데이터 전송이 필요하다면 Data를 출력하고, 동시에 Valid 신호를 전달합니다.
3. 수신하는 부분은 Valid 신호가 발생된 것 보고 처리합니다.
4. 다음 클럭 사이클에 전송하는 부분이 데이터 전송 준비가 안된경우, Valid 신호는 비활성화 합니다.

(가져가기 신호가 발생하지 못하는 경우)
1. 수신하는 부분에서 내부 모듈이 수신 불가능한 경우라 Get 신호가 발생하지 않습니다.
2. 이때 전송하는 부분에서 데이터 전송이 필요하다면 Get 여부와 상관 없이 Data를 출력하고, 동시에 Valid 신호를 전달합니다.
3. 수신하는 부분은 수신 가능한 경우에 바로 Get 신호를 발생하고, 전송하는 부분은 Get 신호가 발생될 때까지 대기합니다.
4. Get이 발생하면 수신하는 부분은 Valid 신호가 발생된 것 보고 처리합니다.
5. 다음 클럭 사이클에 전송하는 부분이 데이터 전송 준비가 안된경우, Valid 신호는 비활성화 합니다.

gen2에서 `Valid && !Get`인 IST → RS 채널은 같은 Valid와 Data를 유지합니다. 일부 채널만 수락되어도 나머지 채널의 위치와 데이터는 바뀌지 않습니다.
NEL → IST는 예외로, NEL이 모든 Get을 확인한 뒤 해당 묶음의 Valid를 발생시킵니다.
PRM → NEL은 번호 할당에 이 규약을 사용하되, PRM 입력 정체 시에는 할당 Valid를 내려 새 rename을 막습니다.
PRM → IST의 준비 완료 통지는 아래의 **Valid 기반 전송**이며 Get이 없습니다.

### Valid 기반 전송 단위의 구체적인 설명
|Signal Name|Direction|Description|
|-|-|-|
|Valid|Sender->Recevier|데이터의 유효성|
|Data|Sender->Recevier|전송되는 데이터|

Valid 신호가 발생하면 해당 데이터를 항상 수신해야 합니다.

간단한 예시를 보이면
1. 전송하는 부분에서 데이터 전송이 필요하다면 Data와 Valid 신호를 전달합니다.
2. 수신하는 부분은 데이터를 수신받고 처리합니다.
3. 다음 클럭 사이클에 전송하는 부분이 데이터 전송 준비가 안된경우, Valid 신호는 비활성화 합니다.

### EX 연결을 위한 규칙
아래 포맷은 현재 `gen2` scheduler 경계를 기준으로 합니다.
개념적인 Micro-Op에는 EX Path가 포함되며, RTL에서는 분류와 디코딩을 쉽게 하기 위해 `EX Path`와 `Micro-Opcode`를 별도 필드로 표현합니다.
RS는 EX Path를 포함한 패킷을 그대로 EX에 전달합니다. 소스 레지스터 값 읽기와 결과 값 저장은 이 scheduler 인터페이스 바깥에서 처리합니다.

을숙도 아키텍쳐는 Execution Unit을 모두 커스텀 하고 추가하는 구조입니다.  
이때 사용되는 EX의 명령 포맷과 결과 포맷은 특정한 구조를 가져야 합니다.  
**모든 커스텀 EX 모듈의 입력 명령과 일반 완료 포맷은 동일합니다. 분기 EX는 별도의 분기 결과 채널도 사용합니다.**
LSB부터 MSB로 왼쪽부터 오른쪽으로 입력 명령 포맷을 나타내면
|Program Counter|Flow Index|EX Path|Micro-Opcode|Immediate Value|RD Address|...RS(1~n) Addresses List...|
|-|-|-|-|-|-|-|

형태로 배치됩니다.  
각 필드의 내용은
- **Program Counter**: Instruction Memory에서 해당 명령의 주소입니다.
- **Flow Index**: 해당 명령의 영령 윈도우 번호입니다. 점프/분기로 명령 윈도우가 구분되는데, 이 단위를 Flow Index로 구분됩니다.
- **EX Path / Micro-Opcode**: 실행 유닛 종류와 그 유닛의 명령 구분자입니다. 함께 개념적인 Micro-Op를 구성합니다.
- **Immediate Value**: 명령에 포함된 즉시 입력되는 값입니다.
- **RD Address**: 결과가 저장되는 레지스터 목적지 번호입니다.
- **RS(1~n) Addresses List**: 필요한 레지스터 소스 번호입니다.

LSB부터 MSB로 왼쪽부터 오른쪽으로 일반적인 EX의 출력 결과 포맷을 나타내면
|Program Counter|Flow Index|RD Address|
|-|-|-|

형태입니다. Branch EX도 이 일반 완료 채널을 사용하며, 별도의 분기 결과 채널을 추가로 사용합니다.
분기 결과 채널도 LSB부터 MSB 순서입니다.
|Instruction Program Counter|Flow Index|Resolved Next Program Counter|
|-|-|-|

`i_wbc_result_branch_valid/data`는 분기 명령 자신의 `{Flow, PC}`와 실제 다음 PC를 보고합니다.
조건 분기의 taken/not-taken 모두 실제 다음 PC를 보고하므로 Branch Active 필드는 없습니다.
분기 결과와 일반 `i_wbc_result_valid/data` 완료 보고는 모두 필요합니다.
IM의 lane별 요청/응답과 NEL/FCL 추가 신호는 [FCL의 gen2 인터페이스](flow_control_logic.md#gen2-인터페이스-변경)를 따릅니다.

### 파라미터
을숙도 아키텍쳐는 확장 가능한 구조를 가집니다.  
이에 따라, 파라미터를 이용하여 확장 가능한 RTL 코드를 제공~~하고 있습니다.~~  할 예정입니다.  

동일한 데이터 구조를 복수로 전달하기 위해 파라미터를 사용합니다.

파라미터의 이름 구조는
- ```IS_INST_*```: Instruction Set에 따른 파라미터의 접두사 입니다.  
- ```EX_INST_*```: Execution Unit에 입력되는 명령의 정보에 대한 파라미터의 접두사 입니다.  
**반드시, 모든 커스텀 EX 모듈들의 입출력 정보 파라미터는 공유되어야 합니다.** 
- ```STRUCT_*```: 구조적인 설정을 위해 사용되는 파라미터의 접두사 입니다.

#### Parameter of Instruction Set
Instruction Set에 대한 파라미터입니다. Instruction Set의 명령 포맷 정보를 입력합니다.
- ```IS_INST_PC_BITWIDTH```: Instruction Set에 정의된 명령 메모리의 주소 길이입니다.
- ```IS_INST_PC_STEP```: Instruction Set에 정의된 명령의 주소에서 구분되는 단위입니다.
- ```IS_INST_BITWIDTH```: Instruction Set에 정의된 명령의 길이입니다.
- ```IS_INST_REGS```: Instruction Set에 정의된 범용 레지스터 갯수입니다. CSR과 같은 전용 레지스터는 MicroOP을 이용합니다.
- ```IS_INST_OPERANDS```: Instruction Set에 정의된 명령의 소스 레지스터 수입니다.
- ```IS_INST_IMM```: Instruction Set에 정의된 Immediate 값의 너비입니다.

#### Parameter of Execution Unit
Execution Unit에 대한 파라미터입니다. 상단 포맷에 맞게 EX의 명령 포맷 정보를 입력합니다.
- ```EX_INST_MICROOP_BITWIDTH```: Execution Unit용 명령의 비트 너비입니다.

#### Parameter of EULSUKDO Structure
을숙도 아키텍쳐의 구조에 대한 파라미터입니다. 원하는 구조에 대한 정보를 입력합니다.
- ```STRUCT_DECODE_NEW_INST```: 한 사이클에 Instruction Memory로 부터 입력되는 명령어의 최대 개수이며, 한번에 디코딩 되는 단위와 동일합니다.
- ```STRUCT_INST_STATE_ENTRIES```: Instruction State Entry 갯수입니다.
- ```STRUCT_PHYREGS```: 내부 레지스터 갯수입니다.
- ```STRUCT_EX_PATH```: Execution Unit의 종류입니다. 만약 BRANCH유닛x1 ALUx3 LDST유닛x2이면 EX의 종류인 3으로 작성합니다. 
- gen2 RS FIFO의 최소 깊이는 각 EX Path마다 `STRUCT_INST_STATE_ENTRIES`를 사용합니다. 별도의 `STRUCT_RS_DEPTH` 파라미터는 현재 없습니다.
- ```STRUCT_RS_OUT_ENTRY[STRUCT_EX_PATH]```: EX_PATH에 따른 RS FIFO에서 출력되는 엔트리의 갯수입니다.  
각 EX_PATH에 따른 EX 유닛 수와 동일합니다.
- ```STRUCT_EX_CORES```: Execution Unit의 총 개수 입니다. 만약 BRANCH유닛x1 ALUx3 LDST유닛x2이면 EX의 개수인 6으로 작성합니다. 
- ```STRUCT_EX_OUT_RESULT[STRUCT_EX_CORES]```: EX_PATH에 따른 EX에서 출력되는 레지스터 갯수입니다.  
하나의 EX가 여러 레지스터 출력을 수신할 수 있기에 ```STRUCT_RS_OUT_ENTRY[STRUCT_EX_PATH]```와는 분리된 속성입니다.
- ```STRUCT_PRM_ENTRY_UPDATE```: Physical Register Mapper에서 상태 변화가 필요한 IST 번호를 전달할때,  
한 사이클에 전송될 (IST 번호, 레지스터 번호) 쌍의 최대 개수입니다.
- ```STRUCT_PRM_ENTRY_BUFFER```: Physical Register Mapper에서 하나의 내부 레지스터 번호에 연결된 IST 번호들이 저장되는 갯수입니다.  
만약 하나의 내부 레지스터 번호에 대해 이 이상 저장된다면, PRM 업데이트가 불가능하여 수신 불가 상태로 대기합니다.  
이후 해당 내부 레지스터가 저장되면 수신되면 수신 가능 상태로 변경합니다.
- ```STRUCT_UNALLOCATE_PHYREG```: Flow Control Logic이 Physical Register Mapper으로 한 사이클에 반환시킬 수 있는 내부 레지스터의 수입니다.
- ```STRUCT_FLOW_WINDOWS```: 점프/분기로 명령 윈도우가 구분되는, Flow Index로 사용되는 윈도우 수입니다.
- ```STRUCT_FLOW_PC_MAX_RANGE```: 명령 윈도우의 Program Counter 최대 범위 입니다.

내부적으로 사용하기 위해 파라미터로 자동 생성되는 상수들은 ```_```로 시작합니다.  
- ```_STRUCT_EX_OUT_RESULT_ALL```: ```STRUCT_EX_OUT_RESULT[STRUCT_EX_CORES]```의 모든 요소 합입니다.  
상수에서 **비트 너비와 위치에 대한 상수가 따로 존재**하고, 이들의 이름 구조는
- ```_BITWIDTH_*```: 데이터 구조에서 사용되는 비트 너비입니다.  
- ```_STARTPOINT_*```: 여러개의 데이터 구조 결합에서, 데이터 구조의 시작 위치 비트 번호입니다.  
- ```_ENDPOINT_*```: 여러개의 데이터 구조 결합에서, 데이터 구조의 끝 위치 비트 번호입니다.  
    - ```_*_LOW_*```: 최소 단위 데이터 구조를 뜻하는 명칭입니다.
    - ```_*_CMB_*n*```: 두개 이상의 단위를 결합한 데이터 구조를 뜻하는 명칭입니다.  
    LSB부터 결합된 순서대로 작성하며, ```n```로 구분합니다.
    - ```_*_IO_*```: 입출력 단위로 구성된 데이터 구조를 뜻하는 명칭입니다.

앞에서 설명한 구조/파라미터를 이용한 상수이기에, 구체적인 *비트 너비와 위치에 대한 상수*들은 따로 기술하지 않습니다.

이들을 결합하여 ```_BITWIDTH_LOW_IS_INST_IMM```, ```_STARTPOINT_CMB_OPCODEnFUNC_OPCODE``` 와 같은 형태로 작성합니다.

## 동작의 예시를 설명해주세요!
동작을 설명하기 위해 RV32I ISA를 사용하고  
아래와 같은 구조를 사용한다고 가정하겠습니다.
- ```STRUCT_DECODE_NEW_INST```: 1
- ```STRUCT_EX_PATH```: 3 (Branch/ALU/LDST 각각 하나씩)
- ```STRUCT_RS_OUT_ENTRY[STRUCT_EX_PATH]```: 1, 1, 1 (Branch/ALU/LDST 각각 하나씩)
- ```STRUCT_EX_CORES```: 3 (Branch/ALU/LDST 각각 하나씩)
- ```STRUCT_EX_OUT_RESULT[STRUCT_EX_CORES]```: 1, 1, 1 (Branch/ALU/LDST 각각 하나씩)
- ```STRUCT_PRM_ENTRY_UPDATE```: 3
- ```STRUCT_PRM_ENTRY_BUFFER```: 4
- ```STRUCT_UNALLOCATE_PHYREG```: 4
- ```STRUCT_FLOW_WINDOWS```: 8
- ```STRUCT_FLOW_PC_MAX_RANGE```: 8

~~구체적인 이해를 위해 위 구조로 체험형 플레이그라운드 웹앱을 추가로 제공합니다.~~  
~~[플레이그라운드 웹앱 링크]()~~  
(아직 없습니다)  

입력되는 예시 RV32I 명령은 
```
ADDI x2, zero, 10
ADDI x3, zero, 7
ADDI x5, zero, zero
loop:
    ADDI x4, x5, 3
    ADD  x5, x3, x4
    BEQ  x2, x5, loop
```
이며, 을숙도 아키텍처 구조 자체는 LDST는 ALU와 동일한 구조를 가지므로 Branch와 ALU의 동작으로만 보여드립니다.  
또한 내부 모듈들이 처리하는 자세한 내용은 각 모듈별 설명페이지에 동일한 구조와 명령으로 설명합니다.

### PC:0, ADDI x2, zero, 10

#### 1. 명령 요청 및 해석 [FCL, NEL]
- **[FCL]** Instruction Memory에 PC: 0번지 명령을 요청합니다.  
현재 분기 명령을 만나지 않았으므로 명령 윈도우인 **Flow Index는 0**입니다.
- **[NEL]** 새로운 명령 `ADDI`를 수신하고 해석합니다.
- 목적지 레지스터 `x2`를 위해 PRM에 새로운 물리 레지스터 번호 할당을 요청합니다.  
PRM의 `allocator_start_one`에 의해 비어있는 물리 레지스터 `P1`이 할당됩니다.
- 소스 레지스터 `zero`(x0)는 값이 0으로 고정된 레지스터이므로  
별도의 물리 레지스터를 할당받지 않고 항상 '준비 완료(Ready)' 상태로 취급됩니다.

#### 2. 상태 저장 및 발급 대기 [IST, PRM]
- **[IST]** 내부 명령 체계(Micro-Op)로 변환된 이 명령은 IST의 비어있는 엔트리(예: `I0`)에 저장됩니다.
- 필요한 소스 레지스터(`zero`)가 이미 준비된 상태이므로,  
이 명령은 IST에 들어가자마자 실행 가능(Ready) 상태가 됩니다.

#### 3. 실행 유닛으로 전달 [RS]
- **[RS]** IST에서 준비가 완료된 `I0` 명령을 받아 RS 내부의 ALU 큐(FIFO)로 전달합니다.
- ALU는 0 + 10 연산을 수행하여 결과값 10을 도출합니다.

#### 4. 결과 브로드캐스트 및 상태 업데이트 [WBC, PRM]
- **[WBC]** 처리가 완료된 레지스터 번호 `P1`을 프로세서 내부(PRM, NEL, FCL)로 전달합니다.
- **[PRM]** `P1`을 기다리는 후속 명령의 IST 번호가 기록되어 있는지 확인합니다.  
대기 중인 명령이 없으므로 상태 변화 없이 대기 상태를 유지합니다.

#### 5. 완료 [FCL]
- **[FCL]** `PC:0` 명령이 완료되었음을 확인합니다.  

*PC가 4, 8일 때는 위 구조와 동일하고 할당되는 레지스터만 달라집니다:*  
*`PC:4`에서 x3는 물리 레지스터 `P2`를 할당받고 값 7을 가짐. `PC:8`에서 x5는 물리 레지스터 `P3`를 할당받고 값 0을 가짐.*

### PC:12, ADDI x4, x5, 3
- **[NEL -> PRM]** 목적지 레지스터 `x4`를 위해 물리 레지스터 `P4`를 할당받습니다.  
소스 레지스터 `x5`는 현재 물리 레지스터 `P3`에 매핑되어 있음을 확인합니다.
- **[IST]** 이 명령은 IST 엔트리 `I3`에 저장됩니다. 소스 레지스터 `P3` 연산이 완료되지 않은 경우,  
명령은 대기(Wait) 상태로 지정됩니다.
- **[PRM]** PRM은 `P3` 레지스터 주소에 대기 중인 IST 엔트리 `I3`을 기록합니다.
- **[WBC -> PRM -> IST]** 앞선 `PC:8` 연산이 끝나 WBC가 `P3` 완료 신호를 전달하면,  
PRM은 이를 수신하여 기록된 `I3` 엔트리에 상태 변경 신호를 송신합니다.  
`I3`는 실행 가능(Ready) 상태로 변경되어 RS로 전달됩니다.

### PC:16, ADD x5, x3, x4
- **[NEL -> PRM]** 목적지 레지스터 `x5`를 위해 PRM에서 새로운 물리 레지스터 `P5`를 할당받습니다.  
소스 레지스터 `x3`는 `P2`, `x4`는 `P4`로 각각 매핑합니다.
- **[IST]** 해당 명령은 IST 엔트리 `I4`에 저장됩니다.  
소스 레지스터인 `P2`와 `P4`의 완료 신호가 모두 확인되면 실행 가능 상태로 변경되어 RS로 발급됩니다.

### PC:20, BEQ x2, x5, loop
- **[NEL]** 분기 명령인 `BEQ`를 수신합니다. 이때 분기 명령 여부를 `FCL`에 전달합니다.  
소스 레지스터 `x2`는 최초 할당된 물리 레지스터 `P1`을, `x5`는 직전 명령에서 할당된 `P5`를 참조합니다.
- **[FCL]** 분기 명령이 입력됨에 따라, 이후 유입되는 명령어들은 새로운 명령 윈도우인 **Flow Index 1**로 할당됩니다.  
또한 Branch EX 유닛이 이 명령을 완료할때 까지 새로운 명령을 요구하지 않습니다.  
Flow Index 0에서 할당된 레지스터 중에 새로운 레지스터로 할당되면서 덮어씌워진 기존 물리 레지스터가 존재할 경우, PRM으로 반환합니다.
- **[WBC -> FCL]** Branch EX 유닛이 `P1`과 `P5`를 비교 연산하여 분기 조건 참(Taken)을 판별하고, 대상 주소(`PC:12`)를 WBC로 출력합니다.  
FCL은 이를 수신하여 `PC:12`부터 명령을 다시 요청합니다.

### 두 번째 루프 진입 (PC:12)

#### 1. 새로운 명령 윈도우 할당 [FCL]
- **[FCL]** 분기 결과에 따라 `PC:12`부터 유입되는 명령어들은 **Flow Index 1** 구간에서 처리됩니다.

#### 2. PC:12, ADDI x4, x5, 3
- **[NEL -> PRM]** 목적지 레지스터 `x4`를 위해 PRM은 비어있는 새로운 물리 레지스터 `P6`를 할당합니다.
- 소스 레지스터 `x5`는 1회차 루프에서 마지막으로 맵핑된 물리 레지스터 `P5`를 참조합니다.

#### 3. PC:16, ADD x5, x3, x4
- **[NEL -> PRM]** 목적지 레지스터 `x5`를 위해 물리 레지스터 `P7`을 할당받습니다.
- 소스 레지스터 `x3`는 `P2`를 참조하고, `x4`는 2회차 진입 시 할당된 물리 레지스터 `P6`를 참조합니다.  
해당 명령은 `P6` 및 `P2`의 준비 상태에 따라 대기 및 발급 과정을 거칩니다.

#### 4. PC:20, BEQ x2, x5, loop 및 자원 반환
- **[EX]** 2회차 루프의 `BEQ` 명령은 불변값인 `x2`(`P1`)과 2회차에서 갱신된 `x5`(`P7`)의 값을 비교 연산합니다.
- **[FCL]** Flow Index 0 (1회차 루프) 구간의 PC 내 모든 명령이 처리 완료되었음을 확인합니다.
- **[WBC -> FCL]** Branch EX 유닛이 `P1`과 `P5`를 비교 연산하여 분기 조건 참(Taken)을 판별하고, 대상 주소(`PC:12`)를 WBC로 출력합니다.  
FCL은 이를 수신하여 `PC:12`부터 명령을 다시 요청합니다.
