# `gen` ISA 디코더 구현 프롬프트

아래 구분선 다음 내용을 새 작업에 그대로 붙여 넣는다. 프로젝트 ZIP이나 로컬 저장소를 함께 전달하지 않아도 소스 확보부터 시작할 수 있다.

---

당신은 EULSUKDO `gen`의 ISA 디코더와 생성기를 다루는 SystemVerilog 개발자다. 이 프롬프트만 받았다면 먼저 최신 저장소를 확보하라. `~/work/EULSUKDO`나 생성된 프로젝트 파일이 이미 있다고 가정하지 말 것.

### 소스와 설정 확보

공식 저장소는 `https://github.com/VARZero/EULSUKDO.git`이다. 현재 알려진 기본 브랜치는 `release_v1`이지만 최신 기본 브랜치와 커밋을 원격에서 확인한다.

```sh
git ls-remote --symref https://github.com/VARZero/EULSUKDO.git HEAD
git clone --depth 1 https://github.com/VARZero/EULSUKDO.git EULSUKDO
cd EULSUKDO
git rev-parse HEAD
```

이미 체크아웃이 있다면 `git status`로 사용자의 미커밋 변경을 보존하고, `git fetch origin` 후 원격 기본 브랜치와 비교한다. 덮어쓰는 `reset`/`clean`을 하지 말고 필요한 경우 별도 작업 디렉터리나 worktree를 사용한다. Git이 없다면 `https://github.com/VARZero/EULSUKDO`의 기본 브랜치에서 **Code → Download ZIP**을 받는다. 브랜치·커밋은 저장소 페이지 또는 `https://api.github.com/repos/VARZero/EULSUKDO`에서 확인한다. 네트워크도 안 되면 아래 설명으로 설계 초안은 작성할 수 있지만, 최신 구현을 확인한 것처럼 말하거나 없는 RTL을 지어내지 말라.

프로젝트 ZIP이 없어도 저장소의 `gen/generator-app/examples/rv32i_3decode_5issue_64p64ist.json`을 기본 설정으로 사용한다. 이 예제에는 3 Decode, Branch 1·ALU 3·Memory 1의 5 Issue, 물리 레지스터 64개, IST 64개, RV32I 기본 명령 40개가 들어 있다. 4 Decode·5 Issue의 다른 예제는 `gen/generator-app/examples/rv32i_4decode_5issue.json`이다. 사용자가 다른 ISA나 설정 JSON을 지정했다면 그것이 우선이다. 서로 다른 커밋의 JSON·생성기·RTL을 섞지 말 것.

같은 커밋에서 다음 파일을 실제로 읽어라.

- `gen/generator-app/src/App.tsx`: Import JSON 스키마, 검증, `Download Project` 호출.
- `gen/generator-app/src/utils/decoderGenerator.ts`: 포맷·명령 구조와 디코더 출력 생성.
- `gen/generator-app/src/utils/rtlGenerator.ts`, `gen/generator-app/src/utils/sourceBundle.ts`: 생성 TOP의 디코더 연결, 프로젝트 ZIP 경로.
- `gen/src/RTL/eulsukdo_scheduler.sv`, `new_entry_logic.sv`, `ready_station.sv`, `flow_control_logic.sv`: 디코드 입력과 EX 이슈의 실제 계약.
- `gen/src/TB_UVM/`, `gen/run_tests.sh`, `gen/VERIFICATION.md`: 현재 회귀와 확인 범위.

공개 생성기 `https://varzero.github.io/EULSUKDO/`에서도 JSON을 `Import`하고 `Download Project`로 결과를 받을 수 있다. ZIP을 풀면 `<프로젝트명>/eulsukdo_cad_config.json`, `<프로젝트명>/RTL/<프로젝트명>_eulsukdo_top.sv`, `RTL/<ISA>_decoder.sv`, `RTL/eulsukdo_rtl/`, 빈 `RTL/ex_rtl/`이 생긴다. 로컬 ZIP이 없더라도 저장소의 생성기·예제 JSON으로 같은 구조를 확인할 수 있다.

### 현재 계약을 기준으로 할 작업

목표는 사용자가 지정한 ISA를 생성기의 포맷과 명령 설정에 반영하고, 생성된 디코더·TOP을 `gen/src/RTL/*.sv`와 함께 검증하는 것이다. 기존 NEL·IST·RS·PRM·FCL 인스턴스와 packed bus 계약을 유지한다. 디코더 출력은 `rd_o`, `rs_o={rs2,rs1}`, `exception_o`, `newreg_alloc_o`, `jump_o`, `jump_reg_o`, `branch_o`, `expath_o`, `microop_o`, `imm_o`다. 기본값과 불법 명령 처리를 확인하고, 목적 레지스터가 x0일 때 물리 레지스터 할당이 되지 않는지도 검사한다.

생성기 JSON은 `projectName`, `scheduler`, `decoder`, `formats`, `instructions`로 구성된다. `scheduler.coresList`의 순서가 `expath_o` 번호를 정하며 `instructions[].exPathId`와 `microop`이 EX 계약이다. `formats[].fields`에는 비트 범위와 `Condition`/`rd`/`rs1`/`rs2`/`imm`/`None` 역할이 있다. 흩어진 즉시값은 이미 `formats[].immediateParts`의 `{sourceMsb, sourceLsb, targetLsb}` 구간으로 조립할 수 있다. `signExtendImmediate`를 켜면 최상위 매핑 비트를 위로 부호 확장하고, 구간 사이의 빈 비트는 0으로 채운다. S형은 `[31:25]→[11:5]`, `[11:7]→[4:0]`; B형은 `[31]→[12]`, `[7]→[11]`, `[30:25]→[10:5]`, `[11:8]→[4:1]`와 `imm[0]=0`; J형은 `[31]→[20]`, `[19:12]→[19:12]`, `[20]→[11]`, `[30:21]→[10:1]`와 `imm[0]=0`을 기준으로 확인한다. 이 설명은 방향을 잡기 위한 것이며 구현 시 최신 소스와 JSON 값이 우선이다.

기본 화면의 ADD/SUB/LW 3개는 전체 ISA가 아니다. 위 3 Decode 예제의 40개는 `FENCE`, `ECALL`, `EBREAK`를 포함하며 `FENCE.I`는 별도 Zifencei 확장이다. 현재 생성기는 인식한 명령의 `exception_o`를 0으로 내므로 `ECALL`·`EBREAK`의 실제 trap 실행과 스케줄러 trap 출력까지 자동 구현되었다고 주장하지 말 것. 필요하면 EX·예외 경로의 계약을 별도로 설계한다. EX가 받을 uop/경로 표와 즉시값·플래그·레지스터 사용 표를 변경 전에 확정한다.

### 검증과 결과물

명령별 대표 인코딩, 동일 opcode 안의 funct 구별, 잘못된 opcode, x0 목적지, S/B/J의 양수·음수 경계 즉시값을 self-checking 테스트로 확인한다. 생성된 TOP·디코더를 `gen/src/RTL/*.sv`와 함께 Verilator lint하고 `gen/run_tests.sh`의 기존 스케줄러 회귀도 유지한다. 생성기 코드를 바꿨다면 `gen/generator-app`에서 `npm ci`, `npm run build`, `npm run lint`를 실행한다. 새 JSON이나 UI 설정을 추가했다면 ZIP 안의 설정 JSON으로 다시 Import할 수 있는지도 확인한다.

사용한 원격 커밋 SHA, 변경 파일, 명령별 지원 범위, 실제 통과한 검사, 미구현된 EX·메모리·trap 동작을 결과에 분리해서 적어라. 파일을 받지 못한 상태라면 확인한 사실과 가정을 구분하고, 정확한 통합에 필요한 소스를 사용자에게 요청하라.
