import { Component, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';

type HealthResponse = {
  status: string;
  service: string;
  timeUtc: string;
};

type RuntimeConfig = {
  apiBaseUrl?: string;
};

declare global {
  interface Window {
    __APP_CONFIG__?: RuntimeConfig;
  }
}

@Component({
  selector: 'app-root',
  templateUrl: './app.html',
  styleUrl: './app.scss'
})
export class App {
  protected readonly title = signal('EKS Platform Health Check');
  protected readonly loading = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly health = signal<HealthResponse | null>(null);

  private readonly apiBaseUrl = this.resolveApiBaseUrl();

  constructor(private readonly http: HttpClient) {
    this.checkHealth();
  }

  protected checkHealth(): void {
    this.loading.set(true);
    this.error.set(null);

    this.http.get<HealthResponse>(`${this.apiBaseUrl}/health`).subscribe({
      next: (response) => {
        this.health.set(response);
        this.loading.set(false);
      },
      error: (err) => {
        const message = err?.error?.message || err?.message || 'Failed to reach backend health endpoint.';
        this.error.set(message);
        this.health.set(null);
        this.loading.set(false);
      }
    });
  }

  protected apiUrlLabel(): string {
    return this.apiBaseUrl;
  }

  private resolveApiBaseUrl(): string {
    const runtimeApi = window.__APP_CONFIG__?.apiBaseUrl?.trim();
    if (runtimeApi) {
      return runtimeApi.replace(/\/$/, '');
    }

    return 'http://localhost:8080';
  }
}
