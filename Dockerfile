# Build frontend
FROM node:23-alpine AS frontend-builder
WORKDIR /app/frontend
COPY frontend/package*.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# Build backend
FROM golang:1.24-alpine AS backend-builder
WORKDIR /app
COPY backend/ ./
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -o main .

# Final stage
FROM alpine:latest
WORKDIR /app
COPY --from=backend-builder /app/main .
COPY --from=frontend-builder /app/frontend/dist ./public
EXPOSE 8080
ENV ALLOWED_ORIGINS="https://flamingo.fly.dev"
CMD ["./main"]
