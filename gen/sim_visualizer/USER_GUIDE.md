# Gen VCD 비주얼라이저 사용 설명서

이 앱은 이미 실행한 `gen` 스케줄러의 VCD와 생성기 JSON을 읽어 신호와 파형을 보여 준다. 브라우저 안에서 RTL을 시뮬레이션하지 않는다.

## 실행과 샘플

저장소 루트에서 `cd gen/sim_visualizer`, `npm ci`, `npm run dev`를 차례로 실행한다. `Gen 테스트 VCD 로드`를 누르면 현재 `gen/src/TB_UVM/tb_eulsukdo_scheduler.sv`를 실행해 만든 `public/gen_sample.vcd`가 열린다. RTL 변경 후 저장소 루트에서 `gen/sim_visualizer/generate_sample.sh`를 실행하면 샘플을 다시 만든다.

![현재 Gen 테스트 VCD를 로드하고 15번 사이클의 FCL을 선택한 실제 화면](docs_img/gen_sample_loaded.png)

현재 샘플은 40개 상승 에지 시점(`CYCLE 0 / 39`)을 포함한다. 캡처한 15번 사이클에서 FCL의 첫 요청 레인은 `valid=1`, `get=0`으로 `WAIT`가 표시되고 `o_im_req_pc_valid=0x1`, `i_im_req_pc_get=0x0`으로 읽힌다.

## 조작

- 왼쪽 FCL, NEL, PRM, IST, RS, EX, WBC를 클릭하면 해당 신호가 오른쪽에 표시된다.
- 상단 처음·이전·재생·다음·마지막 버튼과 슬라이더로 사이클을 바꾼다.
- 파형 패널에서 신호 추가·제거, 좌우 이동, 확대·축소를 한다.
- `VCD 파형 업로드`로 자체 VCD를 열고, `Gen 구조 JSON 업로드`로 생성기 설정을 반영한다.

신호가 VCD에 없으면 `VCD에 없음`으로 표시한다. JSON은 화면의 구조 수치를 바꾸며 신호값은 VCD에서 읽는다. 기본 샘플은 스케줄러 테스트이며 완성된 CPU 실행 프로그램은 아니다.

## 확인

현재 RTL의 테스트벤치로 VCD를 재생성했고, 로컬 앱에서 샘플 로드·FCL 선택·15번 사이클 이동을 확인했다. 앱 build와 lint가 통과했다. lint에는 React effect에서 상태를 설정한다는 경고 1건이 남는다.
