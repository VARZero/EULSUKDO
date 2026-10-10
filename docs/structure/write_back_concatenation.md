# Write Back Concatenation(WBC)
Write Back Concatenation은  
EX에서 처리가 완료된 결과의 Flow Index, PC와  
내부 레지스터 번호를 추출하여 전달하는 모듈입니다.  

![WBC 다이어그램](../img/6_WBC.JPG)

**입력을 분할하여 바로 출력으로 전달하는 구조를 가지기 때문에 내부의 구성과 역할을 따로 서술하지 않습니다.**  
**이 부분은 조합 논리로만 만들어집니다.**

## 수신/송신하는 정보
### 처리가 완료된 결과의 Flow Index, PC, 내부 레지스터 번호를 추출해 전달
WBC는 EX에서 완료된 결과의 Flow Index, PC, 내부 레지스터 번호를 추출하고,  
추출한 결과의 Flow Index, PC, 내부 레지스터 번호를 NEL, PRM, FCL에 전달합니다.  

#### 처리가 완료된 결과를 EX에서 수신
처리가 완료된 결과를 EX들에서 입력받습니다.  
EX의 결과과 출력된 위치는 유효한 데이터 필드와 동일하며,  
gen2에서는 모든 EX가 같은 일반 완료 포맷을 사용하고, 분기 EX는 별도의 분기 결과 채널을 추가로 사용합니다.

데이터 구조는 두가지이며, 첫번째는 별도의 분기 결과 채널이고, 두번째는 모든 EX의 일반 완료 채널입니다.
MSB부터 LSB 순서로 아래와 같고,  
(별도의 분기 결과: `i_ex_result_branch_valid/data`)
|Resolved Next Program Counter|Flow Index|Instruction Program Counter|
|-|-|-|
|[```IS_INST_PC_BITWIDTH```-1:0]|[```_BITWIDTH_STRUCT_FLOW_WINDOWS```-1:0]|[```IS_INST_PC_BITWIDTH```-1:0]|

(일반적인 EX의 결과)  
|RD Address|Flow Index|Program Counter|
|-|-|-|
|[```_BITWIDTH_STRUCT_PHYREGS```-1:0]|[```_BITWIDTH_STRUCT_FLOW_WINDOWS```-1:0]|[```IS_INST_PC_BITWIDTH```-1:0]|

일반 완료는 동시에 `STRUCT_EX_OUT_RESULT_SUM`개, 분기 결과는 `STRUCT_EX_BRANCH`개까지 수신합니다.
소스/결과 값은 scheduler 밖에서 처리하므로 RD Value 필드는 없습니다.
조건 분기의 taken/not-taken 모두 실제 다음 PC를 보내며 Branch Active 필드는 없습니다.
분기 명령은 별도의 분기 결과뿐 아니라 일반 완료도 보고해야 합니다. RD가 0이어도 `{Flow, PC}` 완료는 필요합니다.

**Valid 기반 전송**을 사용합니다.  
gen2의 일반 완료 포트는 `i_ex_result_valid/data`, 분기 결과 포트는 `i_ex_result_branch_valid/data`입니다.

#### 처리가 완료된 결과의 Flow Index, PC, 내부 레지스터 번호를 NEL, PRM, FCL으로 전달
입력 받은 결과에서 Flow Index, PC, 내부 레지스터 번호를 NEL, PRM, FCL으로 내보냅니다. 각각 내보냅니다.  

Flow Index와 PC, 내부 레지스터 번호의 전송단위를 각각 나누어 전달합니다.  
동일한 단위를 묶어 전달합니다. 단, 한쪽으로 모아서 전달하지 않습니다.  
즉, 유효한 필드가 띄엄띄엄 존재할 수 있습니다.  
(Flow Index와 PC)
|Flow Index|Program Counter|
|-|-|
|[```_BITWIDTH_STRUCT_FLOW_WINDOWS```-1:0]|[```IS_INST_PC_BITWIDTH```-1:0]|

(내부 레지스터 번호)
|RD Address|
|-|
|[```_BITWIDTH_STRUCT_PHYREGS```-1:0]|

이 정보는 동시에 _STRUCT_EX_OUT_RESULT_ALL 만큼 전달할 수 있습니다.  

**Valid 기반 전송**을 사용합니다.  
배포용 소스 코드에서 명칭은 ```i/o_(nel/prm/fcl)_(pc/phyreg)_*``` 입니다.  

#### 처리가 완료된 Branch 결과를 FCL으로 전달
Branch EX에서 출력된 결과를 FCL로 내보냅니다.  

데이터 구조는 MSB부터 LSB 순서로 아래와 같고,
|Resolved Next Program Counter|Flow Index|Instruction Program Counter|
|-|-|-|
|[```IS_INST_PC_BITWIDTH```-1:0]|[```_BITWIDTH_STRUCT_FLOW_WINDOWS```-1:0]|[```IS_INST_PC_BITWIDTH```-1:0]|

채널 수는 `STRUCT_EX_BRANCH`입니다. 입력의 Valid와 Data를 그대로 FCL에 전달합니다.
FCL은 기다리는 제어 명령의 `{Flow, PC}`와 일치하는 결과만 사용합니다.

**Valid 기반 전송**을 사용합니다.  
gen2 포트 명칭은 `o_fcl_branch_valid/data`입니다. 상세 제어 규약은 [FCL gen2 인터페이스](flow_control_logic.md#gen2-인터페이스-변경)를 따릅니다.
