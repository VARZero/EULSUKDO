# EULSUKDO gen3 벤치마크 검토용 LLM 대화 문서

아래의 **복사용 프롬프트** 전체를 ChatGPT, Claude, Gemini 등 다른 LLM에
붙여 넣으면 된다. 저장소에 접근할 수 없는 모델도 검토할 수 있도록 필요한
구조와 측정 결과를 이 문서 안에 포함했다.

---

## 복사용 프롬프트

당신은 CPU 마이크로아키텍처, RTL, 성능 모델링에 경험이 있는 설계 검토자다.
아래 자료는 EULSUKDO gen3라는 실험적 CAM-less out-of-order scheduler의
마이크로벤치마크 결과다. 주어진 사실과 아직 검증하지 않은 가설을 구분하여
검토해 달라.

답변할 때 다음 원칙을 지켜 달라.

1. 아래 수치를 실제 애플리케이션, CoreMark, SPEC 또는 상용 CPU의 IPC로
   간주하지 않는다.
2. `측정으로 확인됨`, `구조로부터 추론`, `추가 검증 필요`를 구분한다.
3. 공개 근거가 없는 상용 프로세서의 IPC, 전력, 면적 수치를 만들어내지 않는다.
4. 개선안을 제안할 때 예상 효과뿐 아니라 CAM 비교기 수, 배선, 포트, critical
   path, 검증 복잡도 등의 비용도 함께 설명한다.
5. 필요한 정보가 부족하면 임의로 단정하지 말고, 어떤 측정이나 RTL 정보가
   더 필요한지 말한다.

### 1. 프로젝트 목표

EULSUKDO gen3는 operand tag를 모든 issue queue entry와 연관 비교하는 전통적
CAM wakeup/select 대신, physical register별 dependent-instruction 목록을 통해
소비자를 직접 찾아 깨우는 구조를 실험한다. 목표는 확장 가능한 파라미터형
SystemVerilog scheduler를 만들고, 폭을 늘렸을 때의 IPC 이득과 CAM-less 경로의
비용을 관찰하는 것이다.

주요 처리 흐름은 다음과 같다.

```text
decode
  -> rename / physical-register allocation
  -> IST(instruction state table) allocation
  -> PRM의 physical-register별 dependency 등록
  -> operand가 모두 준비되면 execution path별 ready station으로 이동
  -> issue / execute
  -> completion / writeback
  -> PRM readiness 갱신 및 dependent IST entry wakeup
  -> in-order ROB retirement
```

현재 RTL은 decode 폭, 실행 경로 수, 경로별 issue 폭, IST/ROB/physical-register
크기, dependency queue 깊이, ready-station 깊이 등을 파라미터화한다. 이번
측정에서는 IST와 ROB가 각각 64 entries, physical register가 96개, 각 실행
경로의 ready station이 32 entries다.

### 2. 측정 범위와 한계

- 측정일: 2026-09-13
- 시뮬레이터: Verilator 5.050
- 각 workload: 합성된 240개 명령
- 측정 구간: 첫 decode bundle 수락부터 마지막 ROB retirement까지
- IPC 정의: `retired instructions / measured cycles`
- ALU 실행 latency: 1 cycle
- slow 실행 latency: 기본 4 cycles, 일부 실험은 2 또는 8 cycles
- 실행 유닛은 fully pipelined 모델
- 결과는 pipeline fill/drain 시간을 포함
- 1-wide 기준도 같은 OoO scheduler이며 decode 폭만 1로 제한한 구성

아직 포함되지 않은 것:

- 실제 RISC-V instruction decoder 및 프로그램 실행
- branch predictor, speculative fetch, squash/recovery
- cache, TLB, 실제 LSU, memory ordering, load/store forwarding
- 실제 physical register data bypass network
- 합성 기반 frequency, area, power 결과
- CoreMark, Embench, SPEC 등의 실제 workload

따라서 이 결과는 **scheduler 내부의 합성 instruction stream에 대한 ROB retire
IPC**이며, 완성된 CPU 성능이나 상용 CPU와 직접 비교할 수 있는 점수가 아니다.

### 3. Workload 정의

| 이름 | 명령 구성 | 확인하려는 항목 |
|---|---|---|
| `independent_balanced` | 서로 독립, ALU/slow 50:50 | decode와 균형 issue의 처리량 |
| `serial_raw_chain` | 모든 명령이 직전 결과에 의존, ALU/slow 교대 | latency와 RAW 전달이 겹친 최악 조건 |
| `mixed_pair_chains` | 길이 2의 RAW chain, ALU/slow 75:25 | 짧은 의존성과 ALU 편중이 있는 ILP |
| `slow_path_pressure` | 모두 독립이지만 slow 경로만 사용 | 단일 실행 경로 포화 |
| `alu_raw_chain` | 모두 직전 결과에 의존, 1-cycle ALU만 사용 | scheduler wakeup/전달 경로 자체의 비용 |

### 4. 폭과 실행 포트 구성별 결과

괄호는 slow latency 4인 동일한 1-wide 기준 대비 IPC 변화다.

| 구성 | Decode | Issue ALU+slow | 독립·균형 | ALU/slow 긴 chain | 혼합 pair chain | Slow 집중 | ALU-only 긴 chain |
|---|---:|---:|---:|---:|---:|---:|---:|
| 1-wide 기준 | 1 | 1+1 | 0.968 | 0.182 | 0.956 | 0.968 | 0.249 |
| 균형 2-wide | 2 | 1+1 | 1.875 (+93.7%) | 0.182 (+0.0%) | 1.244 (+30.1%) | 0.945 (-2.4%) | 0.249 (+0.0%) |
| 균형 4-wide | 4 | 2+2 | 3.529 (+264.7%) | 0.182 (+0.0%) | 2.424 (+153.5%) | 1.846 (+90.8%) | 0.249 (+0.0%) |
| ALU 편중 4-wide | 4 | 3+1 | 1.875 (+93.7%) | 0.182 (+0.0%) | 3.333 (+248.6%) | 0.952 (-1.6%) | 0.249 (+0.0%) |

다섯 workload를 동일 가중한 기하평균 speedup은 1-wide 대비 균형 2-wide
1.20x, 균형 4-wide 1.78x, ALU 편중 4-wide 1.46x다. 이 값은 선택한 합성
workload에 민감하므로 대표 성능 점수가 아니다.

### 5. Slow latency 변화: 2-wide, ALU 1 issue + slow 1 issue

| Slow latency | 독립·균형 | ALU/slow 긴 chain | 혼합 pair chain | Slow 집중 | ALU-only 긴 chain |
|---:|---:|---:|---:|---:|---:|
| 2 cycles | 1.905 | 0.222 | 1.244 | 0.976 | 0.249 |
| 4 cycles | 1.875 | 0.182 | 1.244 | 0.945 | 0.249 |
| 8 cycles | 1.818 | 0.133 | 1.244 | 0.916 | 0.249 |

관찰상 독립 명령과 짧은 pair chain은 OoO window가 slow latency의 상당 부분을
숨긴다. 반면 긴 chain은 숨길 독립 명령이 없어 slow latency 2→8에서 IPC가
0.222→0.133으로 40.0% 감소한다.

### 6. 현재 해석과 검토가 필요한 가설

측정으로 직접 확인된 사실:

- 독립·균형 workload에서 균형 2-wide는 peak IPC 2의 93.8%, 균형 4-wide는
  peak IPC 4의 88.2%에 도달했다. 짧은 stream의 fill/drain도 포함한 값이다.
- workload의 경로 비율과 issue-port 비율이 맞을 때 폭 증가 효과가 크다.
- 긴 단일 RAW chain은 decode/issue 폭을 늘려도 빨라지지 않았다.
- ALU-only RAW chain은 모든 폭에서 약 0.249 IPC, 즉 약 4.0 cycles/instruction다.

현재 구조로부터 한 추론이며 추가 계측이 필요한 내용:

- 1-cycle ALU인데 ALU-only chain이 약 4 cycles/instruction인 이유는
  completion → PRM ready 갱신 → IST wakeup → ready station/issue로 이어지는
  여러 단계 사이에 약 3개의 추가 bubble이 있기 때문으로 보인다.
- 전통적인 back-to-back ALU forwarding이 1 cycle 간격의 dependent issue를
  지원한다고 가정하면, 이 합성 chain에서 현재 구조는 목표 1 IPC보다 약 4배
  느리다. 이것은 전체 프로그램이 4배 느리다는 뜻이 아니다.
- CAM-less라는 개념 자체보다 현재 구현의 wakeup pipeline과 ready-station
  진입 시점이 병목일 가능성이 크다.

검토 중인 개선 방향:

```text
1-cycle ALU completion
  -> 소수의 destination tag를 이용한 fast wakeup
  -> dependent ALU instruction의 준비 여부 조기 판정
  -> 제한적인 ALU-to-ALU data forwarding

load/multiply/기타 variable-latency 결과
  -> 기존 PRM dependency list
  -> IST wakeup
  -> ready station
```

즉, 전체 issue queue를 CAM으로 되돌리지 않고 **빠른 ALU 결과에만 작은 tag-only
fast-wakeup/forwarding 경로를 추가하는 hybrid 구조**가 후보이다. 다만 tag
wakeup만으로 실제 operand value가 전달되는 것은 아니므로, scheduler wakeup과
PRF/data bypass를 별도로 설계해야 한다.

컴파일러는 true dependency 자체를 제거할 수 없지만 loop unrolling, multiple
accumulators, instruction scheduling으로 독립 chain을 늘려 숨길 수 있다. 효과는
알고리즘의 associativity 허용 여부, register pressure, code size, branch와 memory
병목에 크게 의존한다. 따라서 현재 합성 결과만으로 컴파일러 적용 후 IPC를
정확히 예측할 수 없다.

### 7. 비교 시 참고할 공개 구조

- Arm Cortex-A7: 공개 자료상 dual-issue in-order 소형 코어다.
- Arm Cortex-A510: 공개 자료상 3-wide in-order 소형 코어다.
- CVA6: scoreboard 기반이며 문서에 operand forwarding과 back-to-back ALU
  instruction 지원이 설명되어 있다.
- BOOM: OoO issue unit에서 ALU 결과의 fast wakeup과 variable-latency 결과의
  slow wakeup을 구분한다.
- Arm Cortex-A76: 4-wide decode OoO 코어지만 front-end, branch prediction,
  memory hierarchy와 실행 자원이 포함된 완성 코어이므로 본 수치와 직접 비교할
  수 없다.

공개 참고 문서:

- Arm Cortex-A7: https://developer.arm.com/community/arm-community-blogs/b/architectures-and-processors-blog/posts/combining-large-and-small-compute-engines---arm-cortex-a7
- Arm Cortex-A510: https://developer.arm.com/community/arm-community-blogs/b/architectures-and-processors-blog/posts/first-armv9-cpu-cores
- CVA6 issue stage: https://docs.openhwgroup.org/projects/cva6-user-manual/03_cva6_design/issue_stage.html
- BOOM issue unit: https://docs.boom-core.org/en/latest/sections/issue-units.html
- Arm Cortex-A76: https://developer.arm.com/community/arm-community-blogs/b/architectures-and-processors-blog/posts/cortex-a76-laptop-class-performance-with-mobile-efficiency

### 8. 검토 요청

먼저 아래 순서로 답해 달라.

1. 결과에서 강하게 말할 수 있는 결론 3개와, 아직 말하면 안 되는 결론 3개를
   분리한다.
2. ALU-only RAW chain의 약 4 cycles/instruction을 설명할 수 있는 pipeline
   timing을 cycle-by-cycle로 가정해 그린다. 가정은 명시한다.
3. CAM-less의 장점을 최대한 보존하면서 dependent ALU issue 간격을 줄일 설계안
   2~3개를 제시하고 성능, 전력, 면적, timing, 검증 난이도를 비교한다.
4. 위 결과만으로는 알 수 없는 PPA 항목과, 합성 후 반드시 뽑아야 할 지표를
   정리한다.
5. 다음 실험을 우선순위 순으로 5개 제안한다. 각 실험이 어떤 가설을 판별하는지
   포함한다.
6. 소형 in-order 또는 저전력 OoO 코어를 목표로 할 때 2-wide 1+1, 4-wide
   2+2, 4-wide 3+1 중 어느 방향이 타당한지 조건부로 판단한다.
7. 내 해석에 논리적 오류나 benchmark bias가 있으면 직접 지적한다.

답변 마지막에는 다음 표를 작성해 달라.

| 우선순위 | 변경 또는 실험 | 기대 이득 | 주요 비용/위험 | 판정에 필요한 측정값 |
|---:|---|---|---|---|

---

## 목적별 추가 질문

위 복사용 프롬프트 뒤에 원하는 질문 하나를 덧붙이면 된다.

### 마이크로아키텍처 검토

```text
현재 completion→PRM→IST→RS 경로를 기준으로, full CAM issue queue 없이
back-to-back ALU dependency를 지원할 수 있는 cycle-accurate 구조를 제안해 줘.
제어 tag 경로와 실제 operand data 경로를 분리해서 설명하고, 잘못된 조기
wakeup 및 replay가 필요한 경우까지 다뤄 줘.
```

### 저전력/PPA 검토

```text
전통적인 associative wakeup/select와 이 PRM dependency-list 방식, 그리고
제안된 hybrid fast-wakeup을 비교해 줘. 정량 자료가 없는 항목은 숫자를
추정하지 말고, compare activity, fan-out, wire length, SRAM/register 구현,
read/write port, clock gating 관점에서 어떤 합성·전력 보고서를 비교해야 하는지
실험 계획을 만들어 줘.
```

### 컴파일러 최적화 검토

```text
이 구조를 위한 컴파일러 scheduling을 설계한다고 가정해 줘. true dependency가
강한 reduction, 여러 독립 accumulator를 만들 수 있는 loop, memory-bound loop를
나누어 적용 가능한 변환과 한계를 설명해 줘. 현재 IPC만으로 임의의 최종 IPC를
만들지 말고, 추가 trace를 통해 예측 범위를 구하는 방법을 제안해 줘.
```

### 벤치마크 방법론 검토

```text
현재 다섯 합성 workload와 240-instruction 측정 구간이 폭 확장성과 wakeup
latency를 공정하게 보여 주는지 비판적으로 검토해 줘. warm-up/steady-state,
의존 거리, execution mix, ROB/IST pressure, physical-register pressure, branch,
cache miss, load-use를 포함하는 다음 benchmark matrix를 구체적으로 설계해 줘.
```

### 쉬운 설명 요청

```text
위 결과를 CPU를 처음 설계하는 사람도 이해하도록 자동차 도로 또는 공장
비유로 설명해 줘. 단, 비유 뒤에는 반드시 실제 용어로 다시 연결하고,
독립 명령 처리량이 높은 것과 긴 RAW chain이 느린 것이 동시에 성립하는 이유를
설명해 줘.
```

---

## 저장소를 함께 제공할 수 있을 때

LLM이 로컬 저장소나 첨부 파일을 읽을 수 있다면 다음 파일을 함께 제공하면
수치와 구현을 더 정밀하게 검토할 수 있다.

- `IPC_ANALYSIS.md`: 측정 해석 및 외부 구조 비교
- `results/ipc_summary.csv`: 40개 원시 결과
- `results/ipc_table.md`: 전체 결과 표
- `src/TB/tb_eulsukdo_ipc.sv`: workload 생성 및 IPC 측정 방식
- `src/RTL/eulsukdo_gen3.sv`: top-level 연결
- `src/RTL/eulsukdo_physical_register_mapper.sv`: dependency 목록과 wakeup
- `src/RTL/eulsukdo_instruction_state_table.sv`: operand ready 상태와 select
- `src/RTL/eulsukdo_ready_station.sv`: 실행 경로별 ready queue와 issue

