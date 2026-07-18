# 학습

## 1. 히스토리: ACE와 POSA

`lib/reactor.mli`의 이름은 우리가 지어낸 것이 아니라 물려받은 것입니다. 출처는
**ACE**(ADAPTIVE Communication Environment) — Douglas C. Schmidt가 1990년대 초
Washington University in St. Louis에서 시작한 C++ 네트워크 프로그래밍
프레임워크입니다.

당시의 문제의식은 두 겹이었습니다.

- **이식성.** Solaris, HP-UX, AIX, Windows가 소켓·스레드·공유메모리·시그널 API를
  제각각 다르게 제공했습니다.
- **반복되는 구조.** 그 위에서 매번 같은 동시성 골격 — 이벤트 루프, 커넥션 수락,
  스레드 풀 — 을 손으로 다시 짰습니다.

ACE는 이를 층으로 나눠 풀었습니다. OS 적응 계층(플랫폼 차이를 덮는 얇은 C 래퍼),
C++ 래퍼 파사드(`ACE_SOCK_Stream`, `ACE_Thread_Mutex` 같은 RAII 타입), 그 위의
**프레임워크 계층**(`ACE_Reactor`, `ACE_Proactor`, `ACE_Acceptor`, `ACE_Task` …),
그리고 네이밍·로깅 같은 분산 서비스.

중요한 것은 순서입니다. **패턴이 먼저 있고 구현이 따라온 게 아니라 그 반대**입니다.
ACE를 만들며 반복해서 나타난 구조를 사후에 문서화한 결과가 아래 문헌들입니다.

| 연도 | 문헌 | 내용 |
|---|---|---|
| 1995 | Schmidt, "Reactor: An Object Behavioral Pattern for Demultiplexing and Dispatching Handles for Synchronous Events" (PLoP) | Reactor 단독 논문 |
| 1996–97 | Schmidt et al., Active Object / Acceptor-Connector / Half-Sync-Half-Async 논문들 | 개별 패턴 |
| 2000 | *Pattern-Oriented Software Architecture* Vol. 2 — *Patterns for Concurrent and Networked Objects* (POSA2) | 위 패턴들의 정본 |

ACE 자체의 가장 유명한 파생물은 **TAO**(ACE 위에 얹은 실시간 CORBA ORB)이고,
통신·항공우주·방위·금융 시스템에 실제로 투입됐습니다. 학술 프로젝트로 시작했지만
상용 이력이 두꺼운 편입니다.

**지금 ACE의 위상.** 유지보수는 계속되고 TAO 레거시도 남아 있지만, 신규 프로젝트가
고르는 물건은 아닙니다. C++98 시절 설계라 매크로가 많고 API가 무겁고, C++11 이후
표준 라이브러리가 스레드·뮤텍스·시간을 흡수했으며, 비동기 I/O는 Boost.Asio가 사실상
표준 자리를 가져갔기 때문입니다. 그래서 **오늘날 ACE의 가치는 코드보다 어휘**에
가깝습니다. libuv·Netty·Asio·Eio를 읽을 때 쓰는 용어가 대체로 이 계보이고,
`Reactor`라는 이름도 그 어휘를 빌려온 것입니다.

---

## 2. Reactor

**한 문장.** 하나의 스레드가 한 곳에서 블록하고, 깨어난 뒤 준비된 핸들에 대응하는
핸들러만 골라 디스패치합니다.

풀려는 문제는 이렇습니다. 이벤트 소스가 여러 개일 때 각각에 스레드를 붙이면 컨텍스트
스위칭과 동기화 비용이 커지고, 하나씩 순회하며 블로킹 read를 하면 한 소스가 조용할 때
나머지가 굶고, 바쁜 폴링은 CPU를 태웁니다.

참여자는 다섯입니다.

| 참여자 | 역할 |
|---|---|
| Handle | OS 이벤트 소스 식별자 (fd, 소켓) |
| Synchronous Event Demultiplexer | 여러 handle을 한 번에 기다리는 블로킹 호출 (`select`/`poll`) |
| Initiation Dispatcher (= Reactor) | 등록/해제 API를 제공하고 루프를 소유 |
| Event Handler | 이벤트 발생 시 호출될 인터페이스 |
| Concrete Event Handler | 실제 처리 로직 |

흐름: 핸들러 **등록** → demultiplexer로 **블록** → OS가 깨움 → 준비된 handle의
핸들러 **콜백** → 다시 블록.

**왜 "reactor"인가.** 제어 흐름이 뒤집혀 있기 때문입니다. 애플리케이션이 "읽어줘"라고
호출하는 게 아니라, 핸들러를 등록해두면 프레임워크가 애플리케이션을 호출합니다
(Hollywood principle — "우리가 부를 테니 먼저 전화하지 마세요"). 애플리케이션 코드는
요구하는 쪽이 아니라 도착한 이벤트에 *반응*하는 위치에 놓입니다.

**Troupe에서.** `lib/reactor.mli`는 정통 Reactor의 축약형입니다. 정통 Reactor는
리액터가 `handle → handler` 레지스트리와 `handle_events()` 루프를 직접 소유하지만,
우리 `Reactor.S`는 레지스트리를 갖지 않고 디스패치할 콜백을 `wait`의 인자로 받습니다.
루프와 "누구를 깨울지"에 대한 지식은 `Scheduler`에 있습니다. 즉 **demultiplexing만
떼어내 교체 가능한 백엔드로 만든 형태**이고, dispatcher 역할은 스케줄러가 겸합니다.
`ACE_Reactor`가 `ACE_Select_Reactor` / `ACE_Dev_Poll_Reactor` / `ACE_WFMO_Reactor`를
가졌던 것과 `Reactor.S` 뒤의 `Select` / `Poll`은 같은 발상입니다.

---

## 3. Proactor

**한 문장.** Reactor가 *readiness*("읽을 준비가 됐다, 이제 네가 읽어라")를 알린다면,
Proactor는 *completion*("읽기가 이미 끝났다, 여기 버퍼")을 알립니다.

I/O를 OS에 통째로 위임하고, 완료 이벤트만 큐에서 꺼내 완료 핸들러를 부릅니다. 추가
참여자는 비동기 연산 처리기(OS), 완료 이벤트 큐, Completion Handler입니다.

| | Reactor | Proactor |
|---|---|---|
| 알림 시점 | 준비됨 | 완료됨 |
| 실제 read/write 수행 주체 | 애플리케이션 | OS |
| 버퍼 소유 | 콜백 시점에 애플리케이션이 준비 | 연산 시작 시점에 미리 넘김 |
| 대표 구현 | `select`/`poll`/`epoll`/`kqueue`, libuv, Netty | Windows IOCP, Linux io_uring, Boost.Asio |

Proactor는 syscall 왕복이 적어 유리할 수 있지만, 버퍼 수명 관리가 까다롭고
플랫폼별 편차가 큽니다.

**Troupe에서.** 우리는 Reactor 쪽에 남았습니다. `design.md`의 io_uring 배제 근거
(보안 이슈 이력, 강화된 환경에서의 비활성화)가 곧 Proactor를 택하지 않은 이유이기도
합니다. 애초에 TUI 규모 — 디스크립터 한두 개 — 에서 얻을 것이 없습니다.

---

## 4. Acceptor-Connector

**한 문장.** *연결을 맺는 일*과 *연결된 뒤 하는 일*을 분리합니다.

서버 코드를 짜다 보면 `accept` 루프 안에 프로토콜 처리가 섞이고, 클라이언트 코드에는
같은 프로토콜 처리가 `connect` 뒤에 다시 복사됩니다. 이 패턴은 그 접합부를 끊습니다.

- **Acceptor** — 수동적으로 연결을 기다렸다가 받습니다.
- **Connector** — 능동적으로 연결을 겁니다(비동기 연결도 가능).
- **Service Handler** — 연결이 성립한 뒤의 로직. **양쪽이 공유합니다.**

핵심 이득은 대칭성입니다. 서비스 핸들러는 자신이 연결을 걸었는지 받았는지 몰라도 되고,
연결 수립 전략(블로킹/논블로킹/재시도)과 전송 방식을 서비스 로직을 건드리지 않고
바꿀 수 있습니다. Acceptor/Connector는 보통 Reactor 위에 얹혀 동작합니다.

**Troupe에서.** 아직 해당 사항이 없습니다. Troupe는 네트워크 라이브러리가 아니고
연결 수립 개념이 없습니다. 다만 훗날 소켓을 다루는 액터를 짤 일이 생기면, "연결을
만드는 액터"와 "연결 위에서 말하는 액터"를 나누라는 조언으로 읽으면 됩니다.

---

## 5. Active Object

**한 문장.** 메서드 *호출*과 메서드 *실행*을 분리해, 각 객체가 자기 실행 흐름을
갖게 합니다.

Troupe와 가장 가까운 패턴입니다. 참여자는 여섯입니다.

| 참여자 | 역할 |
|---|---|
| Proxy | 클라이언트가 보는 평범한 인터페이스. 호출을 객체로 바꿔 큐에 넣습니다 |
| Method Request | 예약된 호출 하나를 표현하는 객체 (인자 포함) |
| Activation List | 대기 중인 method request들의 큐 |
| Scheduler | 자기 스레드에서 돌며 큐에서 꺼내 실행 순서를 정합니다 |
| Servant | 실제 구현. 오직 scheduler 스레드에서만 실행됩니다 |
| Future | 호출자가 결과를 나중에 받는 통로 |

이득은 두 가지입니다. 호출자가 블록되지 않고, servant 상태에 **한 스레드만**
접근하므로 내부에 락이 필요 없습니다. 동기화를 데이터가 아니라 경계에 몰아넣는
방식입니다.

**Troupe에서.** 대응이 거의 일대일입니다.

| Active Object | Troupe |
|---|---|
| Activation List | `Mailbox` |
| Method Request | 메시지 |
| Servant | 액터 본문 |
| Scheduler | `Scheduler` |
| Proxy | `Address` + `cast` / `send` |

차이도 분명합니다.

- **스레드 대신 효과.** Active Object는 객체마다 OS 스레드를 전제하지만, Troupe의
  액터는 파이버이고 중단은 일회성 연속(one-shot continuation)으로 표현됩니다.
- **Method Request 객체가 없습니다.** 액터 본문이 직접 메시지를 패턴 매칭하므로
  호출을 객체로 감싸 되살릴 필요가 없습니다.
- **선택적 수신(selective receive).** Active Object의 scheduler는 큐 앞에서부터
  실행 가능한 것을 고르지만, Troupe는 액터가 조건을 제시하고 그에 맞는 메시지를
  큐 중간에서 꺼냅니다. 이쪽은 ACE가 아니라 Erlang 계보입니다.

덧붙여, **액터 모델 자체는 ACE에서 온 것이 아닙니다.** Hewitt이 1973년에 제안했고
Erlang이 실용화했습니다. Active Object는 같은 아이디어에 OO/C++ 어휘를 입힌 사촌쯤으로
보는 편이 정확합니다.

---

## 6. Half-Sync/Half-Async

**한 문장.** 시스템을 비동기 층과 동기 층으로 나누고 그 사이에 큐를 둬서, 성능은
비동기로 얻고 코드는 동기처럼 씁니다.

이건 개별 객체 패턴이 아니라 **아키텍처 패턴**입니다. 세 층으로 구성됩니다.

```
  [ 동기 서비스 층 ]   블로킹하듯 직선적으로 쓰인 애플리케이션 로직
        ↕
  [   큐잉 층      ]   두 층을 떼어놓는 완충 지점
        ↕
  [ 비동기 서비스 층 ]  인터럽트/이벤트 루프. 절대 블록하지 않음
```

동기가 부여인 이유는 이렇습니다. 비동기 코드는 빠르지만 제어 흐름이 콜백으로
찢어져 읽고 디버깅하기 어렵고, 동기 코드는 읽기 쉽지만 블록합니다. 이 패턴은 둘을
층으로 갈라 각자 잘하는 것만 하게 합니다. 대가는 층 사이의 큐 통과 비용 —
컨텍스트 스위칭과 데이터 복사 — 입니다.

**Leader/Followers**는 그 대가를 지우려는 후속 패턴입니다. 큐로 넘기는 대신, 스레드
풀에서 하나("leader")가 이벤트를 기다리다가 이벤트를 받으면 리더 자리를 다른 스레드에
넘기고 자신이 직접 처리합니다. 핸드오프가 사라지는 대신 구조가 복잡해집니다.

**Troupe에서.** 층 구조는 그대로인데 **큐잉 층의 성격이 다릅니다.**

| 층 | Troupe |
|---|---|
| 동기 서비스 층 | 액터 본문. `receive` / `await_readable` / `sleep`을 그냥 호출합니다 |
| 큐잉 층 | 효과 핸들러 경계 (+ 메일박스) |
| 비동기 서비스 층 | `Scheduler` + `Reactor` |

원조는 두 층을 잇기 위해 **스레드와 큐**를 씁니다. Troupe는 **효과**를 씁니다. 액터는
블록하는 것처럼 보이는 코드를 쓰지만 실제로는 `Effect.perform`이 연속을 잘라내고,
스케줄러가 그 연속을 들고 있다가 리액터가 깨우면 재개합니다. 층 사이 데이터 복사도,
스레드 핸드오프도 없습니다.

이게 `design.md`의 첫 설계 원칙 — "제어 흐름에는 효과를" — 이 사는 자리입니다.
Half-Sync/Half-Async가 30년 전에 원했던 것(동기처럼 읽히는 코드 + 비동기 실행)을,
OCaml 5의 효과가 큐 없이 내줍니다.

---

## 7. 요약: Troupe에 남은 것

| 패턴 | Troupe에서의 위치 | 원조와의 차이 |
|---|---|---|
| Reactor | `Reactor.S`, `Select` / `Poll` | 레지스트리·루프 없이 demultiplexing만. 디스패치는 스케줄러 |
| Proactor | 채택하지 않음 | io_uring 배제와 같은 이유 |
| Acceptor-Connector | 해당 없음 | 네트워크 라이브러리가 아님 |
| Active Object | 액터 + `Mailbox` + `Scheduler` | 스레드 대신 파이버, method request 없음, 선택적 수신 추가 |
| Half-Sync/Half-Async | 액터 / 효과 경계 / 런타임의 3층 | 큐·스레드 대신 효과와 일회성 연속 |

---

## 참고 문헌

- D. C. Schmidt, "Reactor: An Object Behavioral Pattern for Demultiplexing and
  Dispatching Handles for Synchronous Events", PLoP, 1995.
- D. C. Schmidt, M. Stal, H. Rohnert, F. Buschmann, *Pattern-Oriented Software
  Architecture, Volume 2: Patterns for Concurrent and Networked Objects*,
  Wiley, 2000.
- C. Hewitt, P. Bishop, R. Steiger, "A Universal Modular ACTOR Formalism for
  Artificial Intelligence", IJCAI, 1973.
- [The ACE ORB / ACE 프로젝트](https://www.dre.vanderbilt.edu/~schmidt/ACE.html)
