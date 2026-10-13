# sse

[![CI](https://github.com/turinglambdaai/sse/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/sse/actions/workflows/ci.yml)

Racket 的 Server-Sent Events 实现：WHATWG 线上格式 + 轻量扇出 hub。这是协议库而不是框架——事件路由、序列化、HTTP 服务器都留给调用者。

## 安装

```
raco pkg install sse
```

## 使用

从任何 `response/output` 风格的服务器上挂一个事件流：

```racket
(require sse
         web-server/http)

(define hub (make-hub))

;; 向所有客户端广播（payload 是纯字符串——JSON 自理）
(hub-notify! hub "edition" "{\"date\":\"2026-10-13\"}")

;; 长连接响应体：retry 提示、重放、15 秒心跳
(define (events-h req)
  (response/output
   (λ (out) (hub-stream hub out))
   #:mime-type #"text/event-stream"
   #:headers
   (list (header #"Cache-Control" #"no-cache")
         (header #"X-Accel-Buffering" #"no"))))

;; 轮询数据源；变化以 "edition" 事件广播
(hub-watch! hub 5 "edition"
            (λ () (and (data-changed?) (jsexpr->string (hasheq 'date (today))))))

;; 不需要 hub 时也可以直接编帧
(sse-encode "msg" "line one\nline two")
;; => "event: msg\ndata: line one\ndata: line two\n\n"
```

你得到什么：

- 符合 WHATWG 的帧编码：多行 data 按 `data:` 行拆分、可选事件 ID、事件名契约校验
- 带单槽重放的扇出 hub，重连客户端立即拿到最新一帧
- 注释心跳与断连检测——死客户端静默摘除
- 变化监视助手：基线抑制、错误容忍
- 除 `base` 外零依赖

局限：重放是单槽（每条事件流一个 hub）；连接建立与重连策略由调用者负责。

## 开发

```
raco pkg install --auto --link .
raco test tests
raco setup --check-pkg-deps -l sse
```

## 许可

[MIT](LICENSE)
