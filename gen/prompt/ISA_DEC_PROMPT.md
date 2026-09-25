# `gen` ISA 디코더 구현 프롬프트

다음 내용을 새 작업에 붙여 넣어 사용한다.

---

당신은 `~/work/EULSUKDO`의 SystemVerilog 개발자다. `gen/src/RTL/eulsukdo_scheduler.sv`, `gen/generator-app/src/utils/rtlGenerator.ts`, `gen/generator-app/src/utils/decoderGenerator.ts`, `gen/generator-app/src/App.tsx`를 먼저 읽고 현재 디코더 포트와 기본 ISA 설정을 확인하라.

목표는 생성기의 ISA 디코더를 실제 목표 ISA에 맞게 확장하고, 생성된 `eulsukdo_example_top.sv`와 `gen/src/RTL/*.sv`에 연결해 검증하는 것이다. 기존 `gen`의 NEL·IST·RS·PRM·FCL 인스턴스와 packed bus 계약을 유지한다. 디코더는 `inst_i`에서 `rd_o`, `rs_o={rs2,rs1}`, `exception_o`, `newreg_alloc_o`, `jump_o`, `jump_reg_o`, `branch_o`, `expath_o`, `microop_o`, `imm_o`를 조합 논리로 출력한다. 모든 출력에 기본값을 주고 불법 명령은 `exception_o`로 표시한다. 스케줄러에 trap 출력이 없으므로 exception 이후 처리 정책은 별도로 명시하라.

실행 경로 번호와 uop는 생성기의 `coresList` 및 `instructions` 설정에서 정한다. 기본 ADD/SUB/LW는 예제일 뿐 전체 RV32I 정의가 아니다. 실제 EX 구현과 같은 uop 표를 먼저 확정하고, 명령별 목적 레지스터 할당, 소스 사용, 부호 확장 immediate, 분기/점프 플래그를 표로 작성하라. 현재 생성기의 포맷 필드 모델은 연속 비트 구간 하나를 immediate로 지정한다. B/J/S형처럼 흩어진 비트를 조합해야 하는 명령은 생성 로직을 확장하고 비트별 self-checking 테스트를 추가하라. 표준 RV32I 디코딩을 이미 지원한다고 가정하지 말라.

생성된 디코더와 래퍼를 `gen/src/RTL/*.sv`와 함께 Verilator lint하고, 대표 명령·잘못된 opcode·경계 immediate의 단위 테스트를 실행하라. `gen/run_tests.sh`의 기존 스케줄러 회귀도 유지하라. 생성기 UI/문서까지 변경이 필요하면 함께 갱신하고, 구현한 ISA 범위와 남은 명령을 명확히 기록하라.
