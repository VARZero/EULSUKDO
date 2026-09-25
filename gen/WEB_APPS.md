# Gen 웹 도구

## 구조·ISA 생성기

```sh
cd gen/generator-app
npm ci
npm run dev
```

구조 설정으로 현재 `gen/src/RTL/eulsukdo_scheduler.sv`의 공개 포트에 맞는 `eulsukdo_example_top.sv`를 만들고, ISA 화면에서 `<isaName>_decoder.sv`를 생성한다. RTL 파일 메뉴는 현재 `gen/src/RTL`의 분리된 원본 모듈을 읽는다. JSON Export/Import 설정은 비주얼라이저에서도 사용할 수 있다. [사용 설명서와 실제 화면](generator-app/USER_GUIDE.md)

기본 ADD/SUB/LW는 예제 명령이다. 래퍼에 IM, EX, 데이터 메모리 구현이 포함되지는 않는다. EX에서 값 데이터가 오가지 않는 현재 WBC 패킷 계약은 [EX 프롬프트](prompt/EX_PROMPT.md)에 설명했다.

## VCD 비주얼라이저

```sh
cd gen/sim_visualizer
npm ci
npm run dev
```

`Gen 테스트 VCD 로드`는 현재 `gen/src/TB_UVM/tb_eulsukdo_scheduler.sv`의 실제 실행 기록을 표시한다. RTL 수정 후 샘플을 갱신할 때는 저장소 루트에서 `gen/sim_visualizer/generate_sample.sh`를 실행한다. 개인 VCD와 생성기의 JSON도 업로드할 수 있다. 이 앱은 VCD 신호를 표시하며 브라우저 안에서 RTL을 실행하지 않는다. [사용 설명서와 실제 화면](sim_visualizer/USER_GUIDE.md)

## 현재 확인 결과

두 앱의 빌드와 lint가 통과했다. 생성기의 기본 래퍼·디코더와 현재 RTL의 Verilator lint도 통과했다. 비주얼라이저의 데모 VCD를 현재 RTL에서 다시 만들고, 앱에서 40개 상승 에지 샘플과 FCL 신호를 확인했다. 자세한 RTL 검증은 [VERIFICATION.md](VERIFICATION.md)에 기록했다.
