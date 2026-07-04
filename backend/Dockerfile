FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY app/BackendApi.csproj app/
RUN dotnet restore app/BackendApi.csproj

COPY app/ app/
RUN dotnet publish app/BackendApi.csproj -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app

COPY --from=build /app/publish ./

ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080

ENTRYPOINT ["dotnet", "BackendApi.dll"]
