# 지금 `gen`은 어디까지 확인했나요?

Gen2에서 썼던 모듈 인스턴스를 바탕으로 스케줄러를 연결했습니다. 처음 제공한 Gen4의 동작을 기준으로 맞췄지만, FIFO와 allocator의 시작 사이클은 Gen2 방식 때문에 조금 늦을 수 있습니다. 따라서 아래 결과는 **확인한 입력에서의 동작 검증**입니다. 모든 입력을 넣어 Gen4와 완전히 같다고 증명한 결과는 아닙니다.

## 어떤 구조를 그대로 썼나요?

최상위의 NEL·IST·RS·WBC·FCL·PRM 인스턴스와 NEL의 regfile, IST의 allocator와 상태 저장소, PRM의 mapping bank와 출력 FIFO, RS의 경로별 gather/FIFO를 사용합니다. `allocator`의 초기 번호 채움 FSM과 `U_ALLOC_FIFO`도 남겼습니다.

`fifo_multichan`에는 순서를 지키기 위해 바뀐 부분이 있습니다. 입력 gather, `fifo_regfile`/`fifo_bram`, 출력 gather 단계는 있지만, 원래의 넓은 FIFO 하나를 채널별 FIFO 은행으로 나눴습니다. RF 경로에는 Gen2 입력 FF가 남아 있고 BRAM 경로는 그 FF를 우회합니다. 따라서 저장소 인스턴스 개수와 내부 파이프라인까지 원래 Gen2와 똑같지는 않습니다.

FCL은 flow마다 `flow_detect_unit`을 둡니다. 반환할 물리 레지스터 번호는 FCL 상위의 공유 큐에 저장하므로 `structure_src`의 flow별 반환 FIFO와 내부 구조가 같지는 않습니다.

## 직접 실행하려면?

```sh
cd gen
./run_tests.sh
```

Verilator가 필요합니다. 실패한 테스트가 있으면 그 지점에서 멈추고, 빌드 로그와 산출물은 `/tmp/gen_*`에 남깁니다.

| 테스트 | 확인한 내용 |
| --- | --- |
| `tb_gen2_fifo_order`, RF/BRAM | 깊이 5의 FIFO에서 희소 push/pop, 동시 입출력, flush와 순서 보존을 250사이클 확인 |
| `tb_gen2_allocator_init` | 초기 채움 뒤 ID 1~5 할당과 반환 |
| `tb_gen2_allocator_full` | 128개 ID가 빠짐없이 나오는지 확인 |
| `tb_allocator_sparse` | 두 번째 채널만 선택해도 첫 ID가 남는지, 반환 ID를 다시 쓰는지 확인 |
| `tb_prm_fanout` | 같은 물리 레지스터를 기다리는 여섯 항목에 결과 통지 |
| `tb_ready_station_paths` | 세 EX 경로로의 분배와 출력 순서 |
| `tb_flow_control_logic`, `tb_flow_window_pressure` | 분기, 늦게 온 IM 응답의 폐기, flow 창 포화와 PC ID 재사용 |
| `tb_eulsukdo_scheduler` | PC 요청부터 rename, issue, writeback, 분기 전환까지 연결 |
| `tb_scheduler_two_lane` | 2채널 묶음 내부 우회, wakeup, 같은 목적 레지스터의 반복 쓰기 |
| `tb_scheduler_stream` | 160개 명령 스트림과 정체 후 재개, 물리 번호 반환 |

위 12개 시뮬레이션과 최상위 RTL의 기본·축소 설정 lint 2개가 통과했습니다. `src/TB_UVM`이라는 이름을 쓰지만, 이 테스트들은 UVM 구성요소 대신 스스로 결과를 확인하는 SystemVerilog 테스트벤치입니다.

## 아직 확인하지 못한 부분은요?

임의의 명령·완료 순서를 두 설계에 똑같이 넣는 전수 비교는 하지 않았습니다. FIFO 반환 번호의 재할당 순서도 Gen4의 bitmap allocator와 달라질 수 있습니다. 실제 디코더, EX, 메모리를 모두 연결한 CPU 실행, FPGA 합성, BRAM 추론과 타이밍도 아직 확인하지 않았습니다. 생성기의 기본 ADD/SUB/LW는 예제이고 EX 연산 결과를 계산하는 유닛은 ZIP에 포함되지 않습니다.
