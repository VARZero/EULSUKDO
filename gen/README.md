# 확장 가능한 을숙도 아키텍쳐와 생성기

- `src/RTL/`: NEL, IST, PRM, RS, WBC, FCL 같은 스케줄러 RTL 소스코드 입니다.
- `src/TB_UVM/`: 모듈과 전체 스케줄러를 확인하는 테스트벤치입니다.
- `generator-app/`: 설정한 구조의 top과 디코더, RTL 전체를 ZIP으로 내려받는 생성기입니다. [여기서 ](https://varzero.github.io/EULSUKDO/)쓰시면 됩니다.
- `sim_visualizer/`: 시뮬레이션 VCD에서 실제 신호가 어떻게 움직였는지 보는 앱입니다.
- `prompt/`: ISA 디코더와 EX를 더 만들 때 참고할 프롬프트입니다. LLM으로 생성할때 참고하세요!

제가 검증했던 부분에 대해서는 [검증 기록](VERIFICATION.md)에 적었습니다.  
두 앱의 실행법은 [웹앱 안내](WEB_APPS.md)에 있습니다.
