# EULSUKDO gen3 IPC parameter study

측정일: 2026-09-13  
시뮬레이터: Verilator 5.050  
측정 대상: `gen3` RTL의 decode/rename/IST/PRM/RS/writeback/ROB retire 경로

## 한 줄 결론

을숙도 gen3는 독립성이 충분하면 decode/issue 폭 증가가 거의 그대로 IPC로
이어진다. 1-wide 기준 0.968 IPC였던 독립·균형 workload가 2-wide에서 1.875
IPC(+93.7%), 균형 4-wide에서 3.529 IPC(+264.7%)가 됐다. 반대로 하나의 긴
RAW 체인은 모든 구성에서 0.182 IPC로 같았다. 즉, 폭 자체보다 **명령 수준
병렬성(ILP)과 실행 경로 구성의 일치**가 성능을 결정한다.

이 수치는 완성된 CPU에서 SPEC/CoreMark를 실행한 결과가 아니다. 캐시, 실제
load/store unit, 분기 예측기, TLB 및 실제 명령 디코더를 제외하고 만든 합성
instruction stream의 **ROB retire IPC**다.

## 측정 방법

테스트벤치는 240개 명령을 디코더 경계로 주입하고, 실행 유닛을 fully-pipelined
모델로 대체한다. ALU 경로 latency는 1 cycle, slow 경로 latency는 기본 4
cycle이다. 첫 decode bundle이 수락된 cycle부터 마지막 명령이 ROB에서
retire되는 cycle까지를 측정한다.

```text
IPC = retired instructions / measured cycles
```

매 구성은 같은 RTL을 Verilator가 파라미터별로 다시 elaborate하고 컴파일한다.
1-wide 기준도 같은 OoO scheduler와 두 실행 경로를 사용하되 decode 폭만 1로
제한했다. 따라서 결과는 “gen3 내부 파라미터 증가분” 비교이며, 별도의 단순
in-order CPU와 비교한 값은 아니다.

### Workload

| 이름 | 구성 | 확인하려는 병목 |
|---|---|---|
| `independent_balanced` | 독립 명령, ALU/slow 50:50 | decode 및 균형 issue의 최대 활용 |
| `serial_raw_chain` | 모든 명령이 직전 결과에 의존, ALU/slow 교대 | 실행 latency와 RAW 전달의 결합 한계 |
| `mixed_pair_chains` | 2개짜리 RAW chain, ALU/slow 75:25 | 현실적인 ILP와 ALU 편중 |
| `slow_path_pressure` | 독립 명령이 모두 slow 경로 사용 | 특정 실행 경로 포화 |
| `alu_raw_chain` | 모든 명령이 직전 결과에 의존, 1-cycle ALU만 사용 | CAM-less wakeup 경로 자체의 비용 |

### 주요 구성

| 구성 | Decode | ALU issue | Slow issue | 총 issue | Slow latency |
|---|---:|---:|---:|---:|---:|
| `decode1_dualpath` | 1 | 1 | 1 | 2 | 4 |
| `balanced_2wide` | 2 | 1 | 1 | 2 | 4 |
| `balanced_4wide` | 4 | 2 | 2 | 4 | 4 |
| `alu_heavy_4wide` | 4 | 3 | 1 | 4 | 4 |

IST/ROB는 64 entries, physical register는 96개, RS는 경로당 32 entries로
고정했다. 따라서 아래 비교의 주 변수는 decode 폭, issue 포트 분배, slow
latency다.

## 측정 결과

### 폭과 실행 포트 분배

| 구성 | 독립·균형 | ALU/slow RAW chain | 혼합 pair chain | Slow 경로 집중 | ALU-only RAW chain |
|---|---:|---:|---:|---:|---:|
| 1-wide 기준 | 0.968 | 0.182 | 0.956 | 0.968 | 0.249 |
| 2-wide 1+1 | **1.875** (+93.7%) | **0.182** (+0.0%) | **1.244** (+30.1%) | **0.945** (-2.4%) | **0.249** (+0.0%) |
| 4-wide 2+2 | **3.529** (+264.7%) | **0.182** (+0.0%) | **2.424** (+153.5%) | **1.846** (+90.8%) | **0.249** (+0.0%) |
| 4-wide 3+1 | **1.875** (+93.7%) | **0.182** (+0.0%) | **3.333** (+248.6%) | **0.952** (-1.6%) | **0.249** (+0.0%) |

괄호는 같은 latency-4 1-wide 구성 대비 변화다. 다섯 workload를 동일 가중한
기하평균 speedup은 2-wide 1.20x, 균형 4-wide 1.78x, ALU 편중 4-wide
1.46x다. 이 평균은 workload 선택에 따라 달라지므로 개별 행보다 중요한 절대
지표로 해석하면 안 된다.

### Slow 경로 latency 변화

| Slow latency | 독립·균형 | 긴 RAW chain | 혼합 pair chain | Slow 경로 집중 |
|---:|---:|---:|---:|---:|
| 2 cycles | 1.905 | 0.222 | 1.244 | 0.976 |
| 4 cycles | 1.875 | 0.182 | 1.244 | 0.945 |
| 8 cycles | 1.818 | 0.133 | 1.244 | 0.916 |

각 행은 2-wide 1+1 구성이다. 독립 명령과 짧은 pair chain은 OoO window가
latency를 상당 부분 숨겼다. 긴 RAW chain은 숨길 다른 명령이 없어서 slow
latency 2→8 증가 시 IPC가 0.222→0.133으로 40.0% 감소했다.

전체 40개 원시 결과는 [ipc_summary.csv](results/ipc_summary.csv), 사람이 읽기
좋은 전체 표는 [ipc_table.md](results/ipc_table.md)에 있다.

## 결과 해석

### 1. 2-wide는 독립 코드에서 거의 이상적으로 확장된다

2-wide의 독립·균형 IPC는 1.875로 이론 peak 2의 93.8%다. 240개라는 짧은
stream의 pipeline fill/drain까지 포함했으므로 steady-state에서는 조금 더
2에 가까워질 수 있다.

### 2. 실행 포트 비율이 workload와 맞아야 한다

4-wide 3+1은 ALU 75%인 혼합 workload에서 3.333 IPC로 가장 좋지만, 50:50
workload에서는 slow 포트 하나가 병목이 되어 1.875 IPC에 머문다. 반대로
4-wide 2+2는 50:50 workload에서 3.529 IPC를 내지만 혼합 workload에서는
2.424 IPC다. 총 issue 수만 정할 것이 아니라 예상 instruction mix에 맞춰
`ISSUE_PER_PATH`를 정해야 한다.

### 3. 폭은 직렬 의존성을 해결하지 못한다

ALU/slow가 교대하는 긴 RAW chain은 decode 폭과 issue 포트를 4배로 늘려도
0.182 IPC 그대로다. 더 중요한 ALU-only RAW chain도 0.249 IPC, 즉 약 4.0
cycles/instruction이다. 1-cycle ALU가 있어도 현재
completion→PRM→IST→RS 경로가 약 3개의 추가 bubble을 만든다. 이 영역은 더
넓은 구조보다 wakeup bypass와 결과 forwarding이 효과적이다.

### 4. 한 경로만 넓히면 다른 경로의 IPC가 오히려 소폭 낮아질 수 있다

2-wide 1+1의 slow-only 결과는 0.945로 1-wide의 0.968보다 2.4% 낮았다.
지속 처리량은 대략 1 IPC지만, atomic decode bundle과 ROB의 head retirement,
짧은 stream의 fill/drain 비용이 더해진 결과다. 3+1 역시 slow-only에는 이득이
없다.

## 상용·오픈소스 프로세서와의 위치

아래 표의 외부 프로세서 수치는 이 테스트벤치로 측정한 IPC가 아니라 공식
문서에 공개된 구조적 폭이다. ISA, 캐시, branch predictor, 공정, clock,
compiler 및 workload가 다르므로 gen3 IPC 숫자와 직접 성능 비교할 수 없다.

| 설계 | 공식 문서상 구조 | gen3와의 차이 |
|---|---|---|
| Arm Cortex-A76 | fetch 4~8 instructions/cycle, 4-wide decode, OoO core에 최대 8 operations/cycle dispatch, quad-issue integer | gen3 4-wide와 front-end 폭은 비슷한 급으로 설정할 수 있지만, A76은 고대역 branch prediction, 실제 memory hierarchy, 더 넓은 dispatch/실행 자원을 갖는다. |
| BOOM | fetch/decode/ROB/physical register/issue queue 폭과 크기를 파라미터화하며, 문서 예시는 fetch/decode 1, ROB 64, integer issue 2, memory issue 1, FP issue 1, integer physical registers 96 | 이번 gen3 측정의 ROB 64·physical register 96은 BOOM 예시와 크기만 비슷하다. BOOM은 branch prediction, rename snapshot, misprediction kill, LSQ 등 완전한 speculative core 구조를 갖는다. |
| CVA6 | 기본 scoreboard 기반 issue 구조이며 현재 파라미터에는 superscalar 활성화 시 2 issue/2 commit 옵션이 명시돼 있다 | gen3 2-wide는 독립 workload에서 1.875 retire IPC를 보였지만, CVA6와 동일 binary/메모리 모델로 측정한 값이 아니므로 우열 비교는 불가능하다. gen3의 핵심 차이는 physical rename과 ready instruction의 OoO issue다. |

Cortex-A76 수치는 Arm의 공식 소개 자료에서 가져왔다. Arm은 A76을 최초의
4-wide decode Cortex-A 코어로 설명하고 최대 8 operations/cycle dispatch와
quad-issue integer를 명시한다. [Arm Cortex-A76 공식 microarchitecture 소개](https://developer.arm.com/community/arm-community-blogs/b/architectures-and-processors-blog/posts/cortex-a76-laptop-class-performance-with-mobile-efficiency)

BOOM 문서는 fetch/decode/ROB/issue/physical-register 구성을 직접 파라미터화할 수
있다고 설명한다. [BOOM parameterization](https://docs.boom-core.org/en/latest/sections/parameterization.html),
[BOOM pipeline](https://docs.boom-core.org/en/latest/sections/intro-overview/boom-pipeline.html),
[BOOM ROB](https://docs.boom-core.org/en/latest/sections/reorder-buffer.html). BOOM의
branch unit은 오예측 시 front-end와 inflight uop을 kill하고 rename/predictor
상태를 복구한다. [BOOM execution stages](https://docs.boom-core.org/en/latest/sections/execution-stages.html)

CVA6의 공식 문서는 `SuperscalarEn`에서 2 issue/2 commit을 명시하며, issue
stage가 scoreboard로 source/destination 및 functional-unit 가용성을 검사한다고
설명한다. [CVA6 parameters](https://docs.openhwgroup.org/projects/cva6-user-manual/01_cva6_user/Parameters_Configuration.html),
[CVA6 issue stage](https://docs.openhwgroup.org/projects/cva6-user-manual/03_cva6_design/issue_stage.html)

## gen3에 가장 큰 다음 성능 과제

1. **Branch prediction과 squash**: 현재 gen3는 branch/jump-register 결과가 올
   때까지 fetch를 멈춘다. 이번 IPC sweep은 branch를 제외했기 때문에 실제
   branch-heavy code 성능을 과대평가한다.
2. **완료→발행 bypass**: 긴 RAW chain 0.182 IPC가 가장 명확한 병목이다.
   writeback과 같은 cycle에 dependent instruction을 RS로 넘기는 bypass가
   필요하다.
3. **실제 LSU와 memory ordering**: slow path의 latency만 모델링했으며 cache
   miss, MSHR, load-use forwarding, store ordering은 없다.
4. **실제 instruction trace**: RISC-V decoder/PRF/EX를 연결한 뒤 CoreMark,
   Embench 또는 SPEC 계열의 committed-instruction/cycle을 측정해야 상용·오픈
   소스 코어와 의미 있는 비교가 가능하다.
5. **PPA 동시 측정**: 4-wide의 IPC 향상만으로 최적 구성을 정할 수 없다.
   PRM 포트, IST select, RS FIFO 증가에 따른 area/timing/power를 합성 결과와
   함께 봐야 한다.

## 재현 방법

```sh
cd gen3
make ipc-sweep
```

벤치마크는 [tb_eulsukdo_ipc.sv](src/TB/tb_eulsukdo_ipc.sv), sweep 구성은
[run_ipc_sweep.sh](scripts/run_ipc_sweep.sh), 표 생성은
[summarize_ipc.py](scripts/summarize_ipc.py)에 있다. 새로운 구성을 추가하려면
`run_ipc_sweep.sh`의 `run_config 이름 decode ALU_issue slow_issue slow_latency`
호출을 하나 추가하면 된다.
