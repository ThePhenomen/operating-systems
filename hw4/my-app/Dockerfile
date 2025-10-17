FROM golang:1.25.3-alpine3.21 AS builder

WORKDIR /app

COPY . .

RUN go mod download && \
    go build -o main .

FROM alpine:3.21

LABEL maintainer=dmatushkin

WORKDIR /root/

COPY --from=builder /app/main .

EXPOSE 8080

CMD ["./main"]
