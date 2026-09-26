# EX 기본 구조 설계 프롬프트

아래 **[복사하여 사용할 프롬프트]** 전체를 새 작업에 붙여 넣는다. 프로젝트 ZIP이나 로컬 저장소를 함께 전달하지 않아도, 프롬프트 안의 저장소 주소와 파일 경로에서 현재 소스를 확보하도록 작성했다.

---

## [복사하여 사용할 프롬프트]

당신은 EULSUKDO `gen` 작업본의 **실행부(EX)**를 설계·구현하는 SystemVerilog 개발자다. 이 프롬프트만 받은 경우에도 아래 순서로 최신 소스를 확보하고 진행하라. 프로젝트 파일이나 `~/work/EULSUKDO` 경로가 이미 있다고 가정하지 말 것.

### 프로젝트 파일 없이 시작하기

공식 저장소는 `https://github.com/VARZero/EULSUKDO.git`이다. 먼저 원격 기본 브랜치와 커밋을 확인한다. 현재 알려진 기본 브랜치는 `release_v1`이지만 이름을 고정해서 추측하지 말고 원격 `HEAD`를 기준으로 한다.

```sh
git ls-remote --symref https://github.com/VARZero/EULSUKDO.git HEAD
git clone --depth 1 https://github.com/VARZero/EULSUKDO.git EULSUKDO
cd EULSUKDO
git rev-parse HEAD
```

이미 저장소가 있다면 `git status`로 사용자의 미커밋 변경을 먼저 확인하고, `git fetch origin` 뒤 기본 브랜치의 최신 커밋과 비교한다. 사용자 변경을 덮어쓰는 `reset`/`clean`을 하지 말고 별도 작업 디렉터리나 worktree에서 최신 소스를 사용한다. Git을 쓸 수 없다면 `https://github.com/VARZero/EULSUKDO`에서 기본 브랜치의 **Code → Download ZIP**을 받고, GitHub 저장소 페이지 또는 `https://api.github.com/repos/VARZero/EULSUKDO`에서 브랜치·커밋을 확인한다. 서로 다른 커밋의 RTL과 생성기 파일을 섞지 말 것. 네트워크도 사용할 수 없다면 아래 계약은 작업 초안으로만 쓰고, 최신 코드 확인 없이 호환성이나 검증 완료를 주장하지 말라.

프로젝트 ZIP이 없으면 저장소의 `gen/generator-app/examples/rv32i_3decode_5issue_64p64ist.json`을 기본 ISA/uop 표로 사용한다. 생성기 `https://varzero.github.io/EULSUKDO/`의 `Import`에 이 JSON을 넣고 `Download Project`를 누르면 `<프로젝트명>/eulsukdo_cad_config.json`, `<프로젝트명>/RTL/<프로젝트명>_eulsukdo_top.sv`, `RTL/rv32i_decoder.sv`, `RTL/eulsukdo_rtl/`, 빈 `RTL/ex_rtl/`이 생긴다. 생성된 TOP에는 `// == EX Area START ==`, `// -- EX Instances --`, `// ==   EX Area END   ==` 자리가 있다. 웹앱을 사용할 수 없어도 아래 저장소 파일과 JSON을 읽어 EX를 설계·검증할 수 있다.

다운로드한 **같은 커밋**에서 다음 파일을 실제로 읽고 신호·필드 위치를 확인하라.

- `gen/src/RTL/eulsukdo_scheduler.sv`: RS/EX 이슈와 WBC 완료 포트, 전체 구조 파라미터.
- `gen/src/RTL/ready_station.sv`, `instruction_state_table.sv`, `write_back_concatenation.sv`, `flow_control_logic.sv`, `new_entry_logic.sv`: 패킷 순서, valid/get, branch redirect, wakeup 조건.
- `gen/src/RTL/_element_logics.sv`: 기존 `regfile` 등 재사용할 수 있는 부품.
- `structure_src/RTL/example_ex/{alu,branch,mem}.sv`: 연산 내용과 사용자 의도의 참고 자료. **포트와 비트 배치는 gen가 우선**이다.
- `gen/generator-app/src/utils/rtlGenerator.ts`, `gen/generator-app/src/utils/decoderGenerator.ts`, `gen/generator-app/src/utils/sourceBundle.ts`: 생성 TOP의 EX 자리, 디코더 출력, ZIP 구조.
- `gen/generator-app/examples/rv32i_3decode_5issue_64p64ist.json`: 기본 3 Decode·5 Issue, 물리 레지스터/IST 각 64개, 명령별 경로와 uop. 다른 JSON을 사용자가 지정했다면 그 파일이 우선이다.
- `gen/src/TB_UVM/`와 `gen/VERIFICATION.md`: 기존 성공 조건과 테스트 스타일.

### 목표와 작업 경계

사용자의 명령 흐름인 `IM → Decoder → NEL/PRM → IST → RS → EX → WBC/FCL`을 유지한다. `gen/src/RTL`의 모듈 분리, 기존 파라미터·포트 네이밍, packed bus, 명시적 `always_comb`/`always_ff` 스타일을 지킨다. EX 주변의 새 모듈은 역할별 파일로 분리하고, 기존 RTL은 연결에 꼭 필요한 곳만 바꾼다. `structure_src`의 연산 의미를 참고하되 스케줄러 외부에 실제 값 PRF가 없다는 점을 먼저 확인하고 데이터 경로를 설계하라.

기본 범위는 **정수 ALU + 분기/점프 EX + 물리 레지스터 데이터 저장/읽기 + EX-WBC 연결**이다. 메모리 EX는 별도 경로와 구체적인 메모리 계약을 정의한 후 확장한다. 첫 단계의 성공은 임의의 연산 코드에 대한 형식상 `done`이 아니라, 두 소스 레지스터의 실제 값 읽기, 진짜 결과값, 종속 명령 wakeup, PC 완료/분기 전환까지 통합해서 확인하는 것이다. 별도 ISA/uop 표가 주어지지 않았다면 위 3 Decode·5 Issue JSON을 기준으로 시작하되, 실제 값은 받은 커밋의 JSON에서 다시 읽어라.

### gen와 반드시 일치할 외부 계약

파라미터 이름은 RTL의 `IS_INST_PC_BITWIDTH`, `IS_INST_PC_STEP`, `IS_INST_IMM`, `IS_INST_OPERANDS`, `EX_INST_MICROOP_BITWIDTH`, `STRUCT_PHYREGS`, `STRUCT_FLOW_WINDOWS`, `STRUCT_EX_PATH`, `STRUCT_RS_OUT_ENTRY`, `STRUCT_EX_CORES`, `STRUCT_EX_OUT_RESULT`, `STRUCT_EX_OUT_RESULT_SUM`, `STRUCT_EX_BRANCH`를 사용한다. 단일 EX 경로 숫자를 전체 EX 인스턴스 수로 혼동하지 말 것.

- 이슈 `o_rs_entry_valid[k]`/`i_rs_entry_get[k]`: `valid[k] && get[k]`인 클록에 **한 번만** 레인 `k` 패킷을 소비한다. EX가 바쁘면 `get[k]=0`을 유지한다. `get`을 결과 완료와 직결하면 여러 사이클 연산에서 중복 소비하거나 입력이 사라질 수 있다.
- 각 이슈 패킷은 `o_rs_entry_data[k*EX_INST_WIDTH +: EX_INST_WIDTH]`, LSB부터 `{flow_id, pc}` 태그, EX 경로 번호, uop, immediate, 목적 물리 레지스터, 소스 물리 레지스터들 순서다. 기존 `new_entry_logic.sv`의 `{rs..., rd, imm, microop, expath, tagged_pc}` 연결과 일치시켜라.
- 각 완료 패킷은 `i_wbc_result_data[j*EX_RESULT_WIDTH +: EX_RESULT_WIDTH] = {rd_phy, flow_id, pc}`이다. `i_wbc_result_valid[j]` 한 펄스가 FCL의 해당 명령 완료 **및** PRM/NEL의 rd wakeup으로 전파된다. 결과 버스 자체에는 **32비트 연산 데이터가 없다**. 연산값은 별도의 물리 레지스터 데이터 파일에 기록해야 한다. 실제 rd가 없는 명령도 태그 PC 완료가 필요하며, 예약된 P0의 값/ready 상태를 훼손하지 않도록 하라.
- 분기 결과는 `i_wbc_result_branch_valid[b]`, `i_wbc_result_branch_data[b] = {jump, jump_reg, branch, new_pc}` (`IS_INST_PC_BITWIDTH+3`비트)이다. FCL은 분기 valid가 들어오면 낮은 PC 비트를 리다이렉트에 쓴다. **조건 분기가 안 걸려도** 다음 순차 PC를 목표로 하는 분기 결과를 보내야 FCL의 `flow_wait`가 풀린다. 레지스터 점프 역시 실제 계산한 타깃을 보내라. 디코드 단계에서 목표 PC가 확정되는 직접 점프는 이미 FCL에서 처리하므로 같은 점프를 EX에서 중복 리다이렉트하지 말 것.
- 분기 명령의 branch-result와 동일 명령의 `{rd_phy, tagged_pc}` 완료는 정상적인 타이밍 관계를 갖도록 같은 사이클에 보내는 것을 기본으로 하라. `STRUCT_EX_BRANCH`가 1일 때 동시 분기 완료 두 건을 허용하지 말고, 한 건이 끝날 때까지 보류하라.
- 이슈 tagged PC는 flow ID를 포함한다. EX 파이프라인·메모리 대기·WBC 큐에서 태그와 목적 레지스터를 끝까지 보존한다. 명령을 받지 않았거나 reset된 슬롯에서는 completion을 내지 말 것.

**기본값 비트 예시** (`PC=32`, `FLOW_WINDOWS=8`, `EX_PATH=3`, `uop=5`, `imm=32`, `PHYREGS=64`, `OPERANDS=2`):

| 데이터 | 폭 | LSB부터 필드 위치 |
| --- | ---: | --- |
| RS→EX 1레인 | 92 | tagged PC `[34:0]` (PC `[31:0]`, flow `[34:32]`), expath `[36:35]`, uop `[41:37]`, imm `[73:42]`, rd `[79:74]`, rs1 `[85:80]`, rs2 `[91:86]` |
| EX→WBC 1레인 | 41 | tagged PC `[34:0]`, rd `[40:35]` |
| EX 분기결과 1레인 | 35 | new PC `[31:0]`, branch `[32]`, jump_reg `[33]`, jump `[34]` |

이 숫자는 기본값일 때만 성립한다. 실제 RTL은 `$clog2`와 `+:`를 사용해 파라미터에 맞게 계산하라. EX 유닛당 완료 채널 수가 1이라고 무조건 가정하지 말고 `STRUCT_EX_OUT_RESULT`/`_SUM`의 정의를 조사하라. 여러 유닛이 한 완료 채널을 공유한다면 손실 없는 큐/중재와 수락 규칙을 제시하고 구현하라.

### 모듈을 나눌 기준

1. **EX 어댑터/디멀티플렉서**: 여러 RS 레인의 valid/get을 각 실행 유닛에 연결, 패킷 언팩, 경로별 레인 번호(`sum(STRUCT_RS_OUT_ENTRY[0:path])`) 처리.
2. **PRF 데이터 경로**: `STRUCT_PHYREGS`개의 32비트 실제 값, 소스별 읽기, 완료 시 rd 쓰기, P0 보호, 같은 사이클 WBC→EX 읽기 바이패스. 기존 `regfile`을 재사용할 수 있으면 우선 검토하고 다중 포트 충돌 우선순위를 명시.
3. **ALU EX**: `structure_src`의 정수 ADD/SUB/논리/비교/시프트/즉시값 기본 연산을 입력 uop 표에 맞춰 구현. 연산 지연/파이프라인, valid/get, 결과값·태그 정렬.
4. **Branch EX**: BEQ/BNE/BLT/BGE/BLTU/BGEU, JALR/필요한 PC 연산. `pc + imm`과 `pc + IS_INST_PC_STEP`, JALR 타깃의 ISA별 정렬 규칙을 구분. 실제 분기 판정과 관계없이 한 명령당 PC 완료 및 필요한 branch resolution을 **각각 정확히 한 번** 낸다.
5. **완료 중재와 통합 top**: EX별 결과값을 PRF에 기록하고 WBC에는 정해진 `{rd, tagged_pc}`만 전송. 자원 포화와 reset 동안 패킷 유실/중복 없이 스케줄러를 연결. 생성기에서 내보내는 `eulsukdo_example_top.sv`에도 같은 연결을 적용할 경우 앱의 TypeScript 생성 로직을 함께 수정하고 생성 결과를 lint로 확인.

메모리 경로를 설계한다면 `MEM EX`와 메모리 요청/응답 어댑터를 **별도 모듈**로 추가한다. `structure_src/.../mem.sv`의 기능은 참고하되 그 코드의 버스 타이밍을 사실로 가정하지 말 것. 설계자가 먼저 ready/valid, read data, byte-enable, 정렬, sign extension, store 완료 시점과 한 번만 수행되는 store side effect를 명시한다. 현재 gen에는 LSQ/메모리 순서 보장이 없으므로 임의 OoO store가 안전하다고 주장하지 말 것. LSQ 없이 일단 한 건씩 직렬화할지, 상위 시스템의 ordering 보장을 요구할지 분명히 선택하고 한계를 문서화한다.

### 순서와 검증

1. 먼저 사용한 원격 커밋 SHA와 설정 JSON 경로를 기록한다. 실제 포트/패킷/디코더-uop 표를 추출한 뒤 `ALU / BR / MEM`별 지원 연산을 표로 확정한다. 미정 uop는 임의 할당하지 않는다. gen 생성기의 초기 ADD/SUB/LW는 예제이며, 위 JSON의 40개 RV32I 명령과 구분한다. JSON은 `ECALL`·`EBREAK`를 디코드하지만 실제 trap 처리는 제공하지 않으며 `FENCE.I`는 별도 Zifencei 확장이다.
2. 파일별 책임과 EX-PRF-WBC 연결도를 짧게 기록하고 EX 모듈을 구현한다. 스케줄러의 흐름/할당 알고리즘은 건드리지 않는다.
3. 단위 테스트는 ALU signed/unsigned·shift·immediate·P0, BR taken/not-taken/JALR, ready=0 지속, 동시에 여러 레인 valid, reset 중 미완료 연산 등을 입력/기대값으로 검증한다.
4. 스케줄러 통합 테스트는 `x1 <- 7`, `x2 <- x1 + 5`, 서로 다른 경로에서의 독립 결과, 분기 미실행/실행 후 IM 응답 버리기, tagged PC 및 한 번만 발생하는 WBC, 결과값 PRF 반영을 검사한다. 기존 `gen/run_tests.sh`의 회귀 12개도 유지한다.
5. Verilator lint(기본 및 축소 파라미터), 실행 테스트, 실패 시 VCD 확인 지점을 문서에 실제 실행 결과로 적는다. 통과하지 않은 조건은 명확히 남긴다.

출력물은 구현한 **분리된 `.sv` 파일**, 실제 EX가 연결된 top 또는 예제 top, 실행 가능한 self-checking TB/스크립트, README/검증 결과여야 한다. 알고리즘·코드 스타일은 기존 작성 방식에 맞추고, 모호한 포트 계약을 임의로 채운 경우는 사용자 의도라고 단정하지 말고 근거와 제한을 먼저 적어라. 구현과 검증을 끝낸 뒤 무엇이 실제로 동작하고 무엇이 아직 미구현인지 분리해 보고하라.
