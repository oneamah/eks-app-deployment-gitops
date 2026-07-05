import { Component, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';

type Post = {
  id: number;
  title: string;
  content: string;
  imageUrl?: string | null;
  createdAt: string;
  updatedAt?: string | null;
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
  selector: 'app-post-view-page',
  standalone: true,
  templateUrl: './post-view.component.html',
  styleUrl: './post-view.component.scss'
})
export class PostViewComponent {
  protected readonly loading = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly posts = signal<Post[]>([]);

  private readonly apiBaseUrl = resolveApiBaseUrl();

  constructor(private readonly http: HttpClient) {
    this.loadPosts();
  }

  protected loadPosts(): void {
    this.loading.set(true);
    this.error.set(null);

    this.http.get<Post[]>(`${this.apiBaseUrl}/posts`).subscribe({
      next: (response) => {
        this.posts.set(response ?? []);
        this.loading.set(false);
      },
      error: (err) => {
        const message = err?.error?.message || err?.message || 'Failed to load posts.';
        this.error.set(message);
        this.loading.set(false);
      }
    });
  }

  protected formatUtc(value: string): string {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return value;
    }

    return date.toLocaleString();
  }
}

function resolveApiBaseUrl(): string {
  const runtimeApi = window.__APP_CONFIG__?.apiBaseUrl?.trim();
  if (runtimeApi) {
    return runtimeApi.replace(/\/$/, '');
  }

  return 'http://localhost:8080';
}
