FROM golang:1.24.10-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY src ./src
COPY dump ./dump
RUN CGO_ENABLED=0 go build -mod=readonly -o /route-dump ./dump

FROM scratch
COPY --from=build /route-dump /route-dump
ENTRYPOINT ["/route-dump"]
