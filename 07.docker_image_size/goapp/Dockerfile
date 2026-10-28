FROM golang:1.27-alpine AS builder
WORKDIR /src
COPY . .
RUN go build -o main .

FROM gcr.io/distroless/static-debian12
WORKDIR /app
COPY --from=builder /src/main .
EXPOSE 8080
CMD ["./main"]
