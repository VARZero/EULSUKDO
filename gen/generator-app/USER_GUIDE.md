# Gen 생성기 사용 설명서

이 앱은 구조 파라미터와 ISA 명령 정의를 편집해 현재 `gen` 스케줄러의 래퍼와 디코더 SystemVerilog를 만든다. RTL 파일 메뉴에서는 현재 `gen/src/RTL`의 원본 모듈을 확인하고 내려받을 수 있다.

## 실행

저장소 루트에서 `cd gen/generator-app`, `npm ci`, `npm run dev`를 차례로 실행한다.

## 구조 설정

![현재 Gen 생성기의 구조 설정, 파이프라인, RTL 코드 화면](docs_img/gen_core_current.png)

왼쪽에서 decode 폭, 물리 레지스터와 IST 엔트리 수, EX 경로별 인스턴스 수, PRM 갱신 폭 및 flow 창 수를 편집한다. 가운데 도식은 설정한 실행 경로와 **FIFO allocator**를 표시한다. 오른쪽 `Generated wrapper`는 현재 스케줄러 공개 포트를 사용하는 `eulsukdo_example_top.sv`이다. 파일 선택 메뉴에서 `flow_detect_unit.sv`와 `new_entry_logic_agent.sv`를 포함한 현재 RTL 10개를 각각 볼 수 있다.

## ISA 디코더

![현재 Gen 생성기의 명령 포맷, ADD/SUB/LW 예제와 디코더 코드 화면](docs_img/gen_decoder_current.png)

상단 `DECODER CUSTOMIZER`에서 ISA 이름·포맷 필드·명령 조건·EX 경로·uop·레지스터 할당과 분기 플래그를 편집한다. 기본 ADD/SUB/LW는 예제이며 전체 RV32I가 아니다. S/B/J형의 흩어진 immediate 비트를 만들려면 생성기를 확장해야 한다.

`EXPORT`는 구조와 ISA 설정을 JSON으로 저장하고 `IMPORT`는 복원한다. 이 JSON은 비주얼라이저의 `Gen 구조 JSON 업로드`에도 사용할 수 있다. 생성한 래퍼와 디코더는 `gen/src/RTL/*.sv`와 함께 컴파일한다. IM/EX/데이터 메모리는 별도로 연결해야 한다.

## 확인

현재 앱의 구조·디코더 화면을 열어 캡처했다. 두 화면의 메뉴에서 현재 모듈 목록과 생성 코드를 확인했다. 앱 build/lint 및 기본 래퍼·디코더를 현재 RTL과 함께 묶은 Verilator lint가 통과했다.
