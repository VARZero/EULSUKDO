# Gen2 선택형 LSQ: 순서 FIFO + 준비 명령 순환 FIFO

`gen2/src/RTL/eulsukdo_scheduler.sv`의 `ENABLE_LSQ`로 활성화한다. 기본값은 `0`이며,
비활성화하면 기존 NEL → IST → RS → EX 연결을 그대로 사용한다. 새 최상위 입출력은 없다.
RTL 소스를 명시적으로 나열하는 빌드에는 `gen2/src/RTL/load_store_queue.sv`를 추가해야 한다.

```systemverilog
eulsukdo_scheduler #(
    .ENABLE_LSQ(1'b1),
    .STRUCT_LSQ_ENTRIES(32),
    .STRUCT_LSQ_EX_PATH(2)
) U_SCHEDULER (
    // 기존 포트 연결
);
```

| 파라미터 | 기본값 | 의미 |
|---|---:|---|
| `ENABLE_LSQ` | `0` | 선택한 EX 경로에 LSQ 삽입 |
| `STRUCT_LSQ_ENTRIES` | `32` | 위·아래 FIFO 각각의 명령 수용량. `STRUCT_DECODE_NEW_INST` 이상 |
| `STRUCT_LSQ_EX_PATH` | `2` | LD/ST 전용 EX 경로 번호. decoder의 expath와 일치해야 함 |

경로 번호 2는 기존 기본 배치의 LD/ST 위치다. 다른 배치에서는 해당 번호를 설정한다.
명령의 micro-op을 해석하지 않고 선택한 경로의 **모든 명령**을 직렬화한다.
여러 LD/ST 출력 레인이 있는 경로도 지원하지만, 동시에 실행 중인 메모리 명령은 하나다.
다른 EX 경로의 RS 출력은 기존 연결을 사용한다.

## 두 FIFO의 역할과 동작

아래 FIFO는 NEL → IST 실제 전달 시점에 LD/ST의 `{Flow Window, PC 전체}`를 기록한다.
준비 여부와 무관하며, 묶음 안에서는 낮은 레인 번호가 먼저다. IST가 준비된 명령을
먼저 내보내더라도 아래 FIFO의 순서는 바뀌지 않는다. PC를 축약하지 않는다.

위 FIFO는 RS의 LD/ST 출력에서 준비된 명령을 받는다. 별도 LDST Index를 IST/RS에 추가하지 않고,
기존 EX 명령 전체와 원래 EX 출력 레인 번호를 보관한다. 태그는 명령의 기존 하위 비트를 사용한다.
실제 레지스터 값은 기존 EX/레지스터 파일 경로에서 읽으며, LSQ가 값을 복사하는 것은 아니다.

1. 두 head가 유효하고 불일치하면 위 head를 위 tail로 이동한다. 아래 head는 유지한다.
2. 일치하면 원래 EX 레인에 valid와 명령을 제시한다. EX가 받지 않으면 그대로 유지한다.
3. `o_rs_entry_valid & i_rs_entry_get`으로 수락되면 `in_flight`를 설정한다.
   두 head는 제거하지 않으며, 완료를 기다리는 동안 EX valid를 내려 중복 시작을 막는다.
4. 실행 중인 태그와 일치하는 완료를 받으면 두 head를 함께 제거한다.
5. 다음 명령에 대해 비교를 다시 시작한다. EX 수락과 완료가 같은 사이클인 경우도 처리한다.

위 FIFO는 동기 RAM 읽기와 충돌 시 데이터 전달(forwarding)을 사용한다.
아래 FIFO의 태그 저장소는 동시 입력을 처리하기 위해 내부적으로 뱅크를 나눈다.
각 뱅크는 쓰기 포트 하나를 사용하며 LUT RAM으로 합성할 수 있다. 논리적으로는 순서가 고정된
FIFO 하나이며, 뱅크 경계에 맞춘 물리 저장소 여유분은 추가 명령 수용량으로 사용하지 않는다.
한 사이클에 준비 명령 하나를 받으며, 여러 RS 레인은 round-robin으로 선택한다.
위 FIFO의 RAM 쓰기 포트를 공유하므로 새 준비 명령의 수신과 회전이 겹치면 수신을 먼저 처리한다.
실행 중에도 남은 공간으로 준비 명령을 받을 수 있지만 회전·후속 실행은 하지 않는다.
새 명령 수신이 없고 두 head가 유효·불일치할 때만 회전한다.

## 완료 인터페이스

기존 `i_wbc_result_valid/data` → WBC의 done-PC 경로를 사용한다.
결과 데이터의 기존 형식은 `{physical rd, Flow Window, PC}`이며 LSQ는 태그 전체를 비교한다.
다른 태그의 완료와 EX 수락 전의 완료는 FIFO를 제거하지 않는다.

**Store도 완료 결과를 반드시 보내야 한다.** 목적 레지스터가 없으면 `physical rd=0`으로
원래 태그를 반환한다. 이 완료는 다음 메모리 명령을 시작해도 되는 시점이어야 한다.
Store를 단순히 내부 버퍼에 넣었다는 응답만으로 다음 Load를 허용하면 순서 보장이 깨질 수 있다.
Load 또한 데이터가 준비되고 해당 명령이 완료됐을 때 결과를 보낸다.
다중 결과를 반환하는 실행부라면 같은 명령의 첫 완료가 후속 메모리 실행을 허용할 수 있어야 한다.

현재 FCL의 제어 흐름을 그대로 사용하며 reset은 두 FIFO와 실행 중 상태를 비운다.
분기 예측에 따른 이미 접수된 명령의 선택적 squash, 메모리 예외 복구, 실행 재시도 프로토콜은
이 옵션에 추가하지 않았다. 향후 그런 기능을 넣으면 순서 FIFO와 준비 FIFO에도 취소 처리가 필요하다.
reset 후 실행부가 이전 명령의 지연된 결과를 반환하지 않는다는 기존 인터페이스 전제가 적용된다.

## 공간 보장과 정체

아래 FIFO의 모든 미완료 명령에 대해 위 FIFO의 자리를 예약한 것으로 취급한다.
두 FIFO의 깊이가 같고, 아래 FIFO에서 공간을 얻은 명령만 IST로 들어가므로
뒤 명령이 위쪽을 채워 선행 명령이 들어오지 못하는 교착을 방지한다.
완료 전까지 예약을 반환하지 않는다.

NEL은 전체 decode 묶음을 한 번에 넘기며 valid가 get에 의존한다. 순환 조합 경로를 피하기 위해
아래 FIFO에 **최대 decode 폭만큼** 공간이 있을 때만 접수를 허용한다.
따라서 공간이 부족하면 LD/ST가 없는 묶음도 일시 정체될 수 있다.
묶음의 유효 LD/ST만 실제 저장하므로 무효 레인이나 다른 EX 경로가 FIFO 엔트리를 차지하지는 않는다.

회전 탐색의 지연은 준비 FIFO의 명령 수에 따라 늘어난다. CAM식 전체 검색, 주소 비교,
Store-to-Load forwarding은 구현하지 않는다. 합성·배선 후 LUT/BRAM과 달성 클럭은 별도 측정 대상이며,
기존 LSQ 비활성화 구성의 클럭 결과를 활성화 구성에 적용하지 않는다.

## 검증 실행

WSL/Linux의 Verilator에서:

```sh
python3 gen2/src/TB/run_lsq.py --jobs 3
```

`gen2/build/lsq_regression/`에 구성별 빌드·실행 로그, `results.json`, 소스 해시가 남는다.
단독 테스트만 실행하려면 `--unit-only`를 추가한다.

- 깊이 1, decode 폭과 같은 깊이, 비거듭제곱 깊이, 복수 준비 레인.
- 역순 준비, 포화 상태 회전, 가장 오래된 명령이 마지막에 준비되는 경우.
- EX 정체 중 출력 유지, 완료 전 중복 실행 금지, 같은 PC/다른 Flow Window 구분.
- 무관한 완료, 실행 수락 전 완료, 수락과 같은 사이클의 완료, 실행 중 reset.
- 무작위 입력·출력 정체와 반복 wraparound, 전체 명령 페이로드 보존.
- 스케줄러 옵션 OFF 회귀, ON 상태의 RAW 의존성·물리 레지스터 반환·Flow Window 재사용.
- 옵션 ON 상태의 제어 흐름 테스트: branch/jump와 폐기되는 fetch tail을 포함.

## 2026-10-24 검증 결과

Verilator 5.020에서 **20/20 통과**했다. 기존 OFF 회귀 9개, LSQ 단독 5개,
ON 통합 6개다. 최종 실행 로그와 소스 해시는 `gen2/build/lsq_final/`에 있다.
작은 LSQ를 켜면 유입 제한 때문에 PRM 포화가 발생하지 않을 수 있으므로,
기존 스트레스 테스트의 PRM 포화 발생 요구는 OFF 구성에만 적용한다.
명령 보존·의존성·LD/ST 완료 순서·레지스터 반환 검사는 ON에서도 유지한다.

Vivado 2020.2, `xc7z020clg400-1`에서 LSQ **단독 OOC 합성**도 통과했다.
태그 35비트, EX 명령 92비트, 완료 입력 5개 기준이며 latch와 black box는 없다.

| 깊이 | 순서 입력 폭 | 준비/EX 레인 | LUT | FF | BRAM 타일 |
|---:|---:|---:|---:|---:|---:|
| 32 | 2 | 1 | 519 | 235 | 1.5 |
| 7 | 3 | 3 | 996 | 297 | 1.5 |

BRAM 1.5는 RAMB36 1개와 RAMB18 1개다. 32엔트리 구성의 LUT 중 48개는 아래 FIFO의
distributed RAM이다. 다른 깊이·레인 수의 결과를 깊이만으로 비교하면 안 된다.
위 표는 LSQ 단독 측정값이다. 이후 전체 스케줄러에 통합한 합성·배선도 수행했으며,
**70MHz 새 구현 통과, 전체 33,526 LUT / 13,428 FF / BRAM 45개**를 확인했다.
클럭 경계와 비교 조건은 [전체 구현 결과](../../GEN2_LSQ_FPGA_TIMING.md)를 참고한다.

재현 스크립트는 `gen2/src/TB/synth_lsq.tcl`이며 최종 보고서는
`gen2/build/lsq_synthesis_final/`에 있다.

```sh
vivado -mode batch -source gen2/src/TB/synth_lsq.tcl -tclargs gen2/build/lsq_synthesis
```
