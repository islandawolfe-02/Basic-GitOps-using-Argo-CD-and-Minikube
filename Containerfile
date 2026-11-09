# P1 packaging recipe (owned). Explain each line in the review request.
# Two stages so the MacBook and GitHub Actions need no local .NET SDK. The classroom ran `dotnet publish` on the host
# and copied publish/; here the same publish command runs inside the pinned SDK image instead.

# Build stage: course-pinned .NET SDK 10.0.401, pinned by digest (multi-arch: arm64 on the M2, amd64 on CI runners).
FROM mcr.microsoft.com/dotnet/sdk:10.0.401@sha256:e70cdb7f80b0348f5cb85f19a8f670fca061f033d57eed12fa003d58b0e06317 AS build
WORKDIR /src
COPY app/ ./app/
RUN dotnet publish app/Foundation.csproj -c Release -o /publish --nologo

# Runtime base: the same ASP.NET 10.0.12 image and digest as the classroom guided recipe.
FROM mcr.microsoft.com/dotnet/aspnet:10.0.12@sha256:222759b391a1aaf241166672c8f99b2d4ada452e7b5319f3c6e8f265a37b5ad4
WORKDIR /app

# COPY: only the published output enters the image (no source, no runtime.env, no credentials).
COPY --from=build /publish/ ./

# Listener: port 8080 inside the container (the Service targets the named port http = 8080).
ENV ASPNETCORE_URLS=http://0.0.0.0:8080
EXPOSE 8080

# Entrypoint: start the packaged foundation page + API.
ENTRYPOINT ["dotnet", "Foundation.dll"]
