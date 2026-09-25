# 웹앱 두 개는 어떻게 쓰나요?

## 1. 생성기

구조를 바꿔 보고 싶을 때 쓰는 앱입니다. 디코드 폭, 물리 레지스터 수, EX 경로 같은 값을 정하면 그 설정으로 top을 만듭니다. ISA 화면에서는 명령 포맷과 디코더 출력도 정할 수 있습니다.

```sh
cd gen/generator-app
npm ci
npm run dev
```

상단 `Project Name`을 적고 화면 오른쪽의 `Download Project`를 누르면 `(프로젝트명)_eulsukdo_rtl.zip`을 받습니다. 안에는 `(프로젝트명)_eulsukdo_top.sv`, 디코더, `gen/src/RTL/`에 있는 모듈 10개가 들어갑니다. `Copy Code`는 화면에 선택한 파일 하나만 복사합니다. 설정을 나중에 다시 열고 싶다면 상단 `Export`로 JSON을 저장하면 됩니다.

처음 보이는 ADD/SUB/LW는 예제입니다. 생성기가 EX 연산기나 메모리까지 만들어 주는 것은 아니므로, 그 부분은 직접 연결해야 합니다. 화면별 설명은 [생성기 사용설명서](generator-app/USER_GUIDE.md)에 적었습니다.

## 2. 시뮬레이션 비주얼라이저

스케줄러가 실제로 어떤 신호를 냈는지 보고 싶을 때 쓰는 앱입니다. 위 생성기의 구조 JSON도 읽을 수 있고, 테스트벤치가 만든 VCD에서 사이클별 신호와 파형을 보여 줍니다.

```sh
cd gen/sim_visualizer
npm ci
npm run dev
```

먼저 `Gen 테스트 VCD 로드`를 눌러 보면 됩니다. 이 샘플은 현재 RTL 테스트벤치를 실행해서 만든 기록입니다. RTL을 바꾼 뒤 샘플도 갱신하려면 저장소 루트에서 `gen/sim_visualizer/generate_sample.sh`를 실행하세요. 직접 만든 VCD를 올려도 됩니다. 자세한 버튼 설명과 신호 읽는 법은 [비주얼라이저 사용설명서](sim_visualizer/USER_GUIDE.md)에 있습니다.

## 어디까지 확인했나요?

두 앱의 빌드와 lint를 돌렸고, ZIP 안의 생성 top·디코더·RTL을 함께 Verilator로 검사했습니다. 데모 VCD도 현재 RTL에서 다시 만들고 앱에서 읽었습니다. 스케줄러 RTL 자체의 테스트는 [검증 기록](VERIFICATION.md)을 참고하세요.
