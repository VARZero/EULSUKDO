# Gen2 LSQ ON 전체 스케줄러 합성·배선 결과

2026-10-24, **32엔트리 LSQ를 켠 2d5i 스케줄러는 70MHz 조건으로 새 합성·배치·배선하여 통과했다.**
Vivado 2020.2 / PYNQ-Z2의 `xc7z020clg400-1` 대상이며, 스케줄러 전체 OOC 내부 타이밍 결과다.
실행부·PS7·보드 입출력·비트스트림·실기 검증은 포함하지 않는다.

## 새 합성·배선으로 확인한 결과

| 처음부터 적용한 목표 | 배선 후 setup | Hold | Setup 위반 끝점 | 결과 |
|---|---:|---:|---:|---|
| 75MHz | −0.070ns | +0.074ns | 1 | 미달 |
| **70MHz** | **+0.252ns** | **+0.035ns** | **0** | **통과** |

70MHz 구현은 pulse-width slack도 +5.893ns이며 setup·hold·pulse-width 위반 끝점이 모두 0이다.
43,949개 routable net 전체가 배선되었고 배선 오류는 0개다. 래치·블랙박스·조합 루프·
클럭 누락·제약 없는 내부 끝점도 없다. 75MHz 구현은 43,942개 net 전체 배선, 배선 오류 0개로,
배선 자체는 완료했지만 setup 끝점 하나가 70ps 미달했다.

## 클럭 경계: 각각의 배선을 고정한 STA 재검사

아래는 별도 재합성 결과가 아니다. 완료된 DCP의 배치·배선을 유지하고 `create_clock`만
바꿔 setup·hold·pulse-width를 다시 검사했다. 검색 간격은 0.1MHz다.

| 사용한 배선 | 재검사 클럭 | Setup | Hold | 결과 |
|---|---:|---:|---:|---|
| 75MHz 목표 구현 | 70MHz | +0.883ns | +0.074ns | 통과 |
| 75MHz 목표 구현 | **74.6MHz** | **+0.002ns** | +0.074ns | 경계 통과 |
| 75MHz 목표 구현 | 74.7MHz | −0.016ns | +0.074ns | 실패 |
| 70MHz 목표 구현 | 65MHz | +1.351ns | +0.035ns | 통과 |
| 70MHz 목표 구현 | **71.2MHz** | **+0.011ns** | +0.035ns | 경계 통과 |
| 70MHz 목표 구현 | 71.3MHz | −0.009ns | +0.035ns | 실패 |
| 70MHz 목표 구현 | 75MHz | −0.701ns | +0.035ns | 실패 |

따라서 **새 구현으로 검증한 운용 기준은 70MHz**, 측정한 두 배선 중 가장 높은 통과점은
**74.6MHz**다. 74.6MHz는 여유가 2ps뿐이어서 운용 기준으로 권하지 않는다.
같은 RTL이라도 목표 주기에 따라 배치·배선 결과와 최장 경로가 달라진다.
71.2MHz와 74.6MHz를 RTL의 절대 최대 클럭으로 해석하지 않는다.

## 전체 리소스

| 구성 / 구현 | LUT | FF | BRAM tile |
|---|---:|---:|---:|
| 기존 LSQ OFF / 75MHz 새 구현 | 34,506 | 13,228 | 43.5 |
| LSQ ON / 75MHz 목표 구현 | 33,593 | 13,428 | 45 |
| **LSQ ON / 70MHz 새 구현** | **33,526** | **13,428** | **45** |

70MHz ON 구성은 Zynq-7020 자원의 LUT **63.02%**, FF **12.62%**, BRAM **32.14%**를 사용한다.
통합된 LSQ 인스턴스 자체는 70MHz 구현에서 **510 LUT / 235 FF / BRAM 1.5개**다.
BRAM 1.5개는 RAMB36 1개와 RAMB18 1개를 의미한다.

LSQ를 추가했는데 전체 LUT가 줄어든 결과를 LSQ의 비용이 음수라는 뜻으로 해석하면 안 된다.
75MHz ON 구현의 계층 보고서에서도 PRM은 8,728→7,780 LUT, IST는 13,238→12,677 LUT로
기존 구현과 다른 합성·최적화 결과가 나왔다. 원본 공통 RTL 중 바뀐 것은 최상위 LSQ 연결부뿐이며,
새 `load_store_queue.sv`가 추가됐다. 이전 실행은 최대 4스레드, 이번 실행은 최대 8스레드 설정이다.
이 비교는 두 구현의 전체 사용량 비교이며, 동일 netlist에 LSQ만 물리적으로 더한 면적 비교는 아니다.

## 현재 최장 경로

- **75MHz 목표 구현:** NEL `stage1_reg[44]` → FCL window 1의 `retired_count_reg[4]`.
  새 명령 처리에 따라 창별 반환 대상 물리 레지스터 개수를 갱신하는 경로다. 논리 16단,
  data path delay 13.276ns, setup −0.070ns.
- **70MHz 목표 구현:** PRM의 `U_PRM_OUTPUT_FIFO/out_ord_vg_valid_reg_reg[12]`
  → `GEN_PRM_IST_MAP[0].U_PRM_IST_MAP/reg_mem_reg[3][5]`. PRM 출력 처리에 따라
  대기 매핑 저장소를 갱신하는 경로다. 논리 14단, data path delay 13.652ns, setup +0.252ns.

70MHz 구현에서 LSQ 레지스터를 출발점으로 하는 최악의 경로는 +1.227ns,
LSQ 레지스터를 도착점으로 하는 최악의 경로는 +2.012ns다.
이번 두 구현의 전체 클럭 제한 경로는 LSQ 내부 태그 비교 경로가 아니다.

## 구성과 재현

- `ENABLE_LSQ=1`, `STRUCT_LSQ_ENTRIES=32`, `STRUCT_LSQ_EX_PATH=2`.
- 2 decode / 5 issue, IST 128 entries, physical registers 64, flow windows 8, window range 16.
- `HD.CLK_SRC=BUFGCTRL_X0Y16`, `general.maxThreads=8`.
- 이전 구현과 동일한 Vivado 2020.2 `$countones` 호환 치환을 **합성용 복사본에만** 적용했다.
  원본 RTL은 이번 클럭 측정 중 변경하지 않았다. 두 실행은 동일한 소스 해시를 사용했다.
- 75MHz 요청 주기 13.333333...ns, 70MHz 요청 주기 14.285714...ns.
  도구 보고 주기는 1ps 단위로 각각 13.333ns, 14.286ns다.

```powershell
python gen2/src/TB/run_lsq_fpga.py --mhz 75 --threads 8 --output gen2/build/lsq_fpga_new/75mhz
python gen2/src/TB/run_lsq_fpga.py --mhz 70 --threads 8 --output gen2/build/lsq_fpga_new/70mhz
python gen2/src/TB/summarize_lsq_fpga.py gen2/build/lsq_fpga_new/70mhz
```

기존 산출물을 덮어쓰지 않도록 새 출력 디렉토리를 사용한다. 다른 Vivado 설치는 `--vivado`로 지정한다.
각 실행은 합성·최적화·배치·배선 DCP, 단계별 리포트, 고정 배선 클럭 탐색 결과를 저장한다.

## 검증 범위와 산출물

두 구현 모두 DRC 오류는 없으며 경고 44건이 남는다. 기존 결과와 같은 종류로,
BRAM 비동기 제어 경고 20+20건, 보고 한도 알림 2건, no-routable-load 1건, PS7 없음 1건이다.
보고 한도에 도달한 종류가 있으므로 경고 총수를 모든 실제 위반의 완전한 개수로 해석하지 않는다.
외부 입출력 지연은 제약하지 않았으므로 보드 통합 이후 타이밍은 다시 검증해야 한다.

로컬 루트: `gen2/build/lsq_fpga_20261024/` (Git 제외).

- `pynq_z2_2d5i_70mhz/scheduler_routed.dcp`: 70MHz 조건으로 새 구현하여 통과한 전체 스케줄러.
- `pynq_z2_2d5i_70mhz/routed_timing_summary.rpt`: 70MHz 최종 타이밍.
- `pynq_z2_2d5i_75mhz/sweep/scheduler_routed_70mhz.dcp`: 75MHz 목표 배선을 70MHz로 재검증한, setup +0.883ns 체크포인트.
- `pynq_z2_2d5i_75mhz/sweep/scheduler_routed_74p6mhz.dcp`: 74.6MHz 경계 체크포인트.
- 각 실행의 `manifest.json`: 파라미터, 원본/합성용 소스 SHA-256, 도구 종료 상태.
- 각 실행의 `results.json`, `sweep/results.csv`: 수치 및 판정.

저장소에 포함한 요약 기록: [gen2_lsq_fpga_20261024.json](docs/validation/gen2_lsq_fpga_20261024.json).
LSQ 기능과 완료 인터페이스는 [LSQ 설명](docs/structure/load_store_queue.md)을 참고한다.
