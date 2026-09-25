# gen 구현과 검증

## 목적과 위치

현재 `gen`은 기존 `gen2`를 복사해 별도로 완성한 작업본이며, 이전 `gen`과 `gen2` 대신 이 저장소에 배치했다. 이전 디렉터리는 복구할 수 있도록 휴지통에 보관했다. 동작 기준은 처음 제공된 `gen4` 스케줄러다. FIFO와 이를 이용하는 allocator의 시작 및 출력 시점은 Gen2 파이프라인 때문에 늦어질 수 있다.

## 인스턴스 구조

- 최상위 `eulsukdo_scheduler`의 `U_NEW_ENTRY_LOGIC`, `U_INSTRUCTION_STATE_TABLE`, `U_READY_STATION`, `U_WRITE_BACK_CONCATENATION`, `U_FLOW_CONTROL_LOGIC`, `U_PHYSICAL_REGISTER_MAPPER` 인스턴스를 유지했다.
- NEL의 매핑/ready regfile, IST의 allocator/source/entry/operand ready 저장소, PRM의 allocator/counter/mapping bank/output FIFO, RS의 경로별 gather/FIFO를 실제 데이터 경로에 사용한다.
- `allocator`는 Gen2의 초기 채움 FSM과 `U_ALLOC_FIFO` 인스턴스를 유지한다. 초기 채움에 128-entry 구성에서는 약 64사이클이 필요하다. 희소 채널의 할당과 반환 번호의 재사용을 검증했다.
- `fifo_multichan`은 `U_VG_PUSH`, `U_FIFO_RF` 또는 `U_FIFO_BRAM`, `U_VG_OUT` 단계를 유지하되, **원래의 넓은 단일 FIFO를 채널별 FIFO 은행으로 바꿨다.** 건너뛴 출력 채널을 앞쪽 보관 레지스터로 유지해 순서를 보장한다. RF 경로에는 Gen2 입력 FF가 남아 있다. BRAM 경로는 시뮬레이션 동작을 위해 입력 FF를 우회한다. 따라서 이 모듈의 저장소 인스턴스 개수와 내부 파이프라인은 원본 Gen2와 같지 않다.
- FCL은 flow별 `flow_detect_unit`을 인스턴스하고 flow의 활성/폐기/완료 상태를 분리했다. 반환 번호의 저장소는 상위 FCL에 공유 큐로 둔다. `structure_src`의 flow별 반환 FIFO를 그대로 복제한 구조는 아니다.

## 실행

```sh
cd gen
./run_tests.sh
```

Verilator가 필요하다. 빌드 산출물과 로그는 `/tmp/gen_*`에 생성된다. 스크립트는 하나라도 실패하면 즉시 종료한다.

| 테스트 | 확인 내용 |
| --- | --- |
| `tb_gen2_fifo_order`, RF/BRAM | 깊이 5, 희소 push/pop, 동시 동작, flush, 비 2의 거듭제곱 깊이에서 250사이클의 순서와 배출 |
| `tb_gen2_allocator_init` | 초기 채움 지연, ID 1~5 할당 및 반환 |
| `tb_gen2_allocator_full` | 128개 ID를 빠짐없이 순서대로 할당 |
| `tb_allocator_sparse` | 높은 채널만 선택해도 앞 ID 보존, 반환 ID 재할당 |
| `tb_prm_fanout` | 같은 물리 레지스터의 대기자 6명에게 결과 통지 |
| `tb_ready_station_paths` | 3개 실행 경로 분배와 출력 순서 |
| `tb_flow_control_logic`, `tb_flow_window_pressure` | 분기, 늦은 IM 응답 폐기, flow 창 포화와 안전한 PC ID 재사용 |
| `tb_eulsukdo_scheduler` | 요청부터 rename, issue, writeback, 분기 전환까지 연결 |
| `tb_scheduler_two_lane` | 2채널 묶음 내부 우회, wakeup, 중복 목적 레지스터 매핑 |
| `tb_scheduler_stream` | 160개 명령 스트림과 정체 후 재개, 물리 번호 반환 |

마지막에 최상위 RTL을 기본 설정과 축소 flow/입력 설정으로 각각 lint한다. 테스트는 자체 검사 SystemVerilog 테스트벤치이며 UVM 구성요소를 사용하지 않는다.

## 검증 범위와 차이

위 테스트가 통과해도 임의의 입력 순서에서 Gen4와 사이클 단위 동등성을 증명한 것은 아니다. FIFO 입력 FF 때문에 RF 경로의 가시성은 늦고 allocator 초기 채움 뒤부터 명령을 받을 수 있다. FIFO 반환 번호의 재할당 순서도 Gen4의 bitmap 방식과 달라질 수 있다. 현재 비교는 기능 시나리오 기반이며 동일 자극을 두 설계에 넣는 전수 비교는 없다. 실제 디코더/EX/메모리 연결, 합성, BRAM 추론 및 FPGA 타이밍은 검증하지 않았다.
