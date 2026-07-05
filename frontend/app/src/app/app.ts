import { Component, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';

type HealthResponse = {
  status: string;
  service: string;
  timeUtc: string;
};

type Post = {
  id: number;
  title: string;
  content: string;
  createdAt: string;
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
  protected readonly title = signal('EKS Platform Health And Posts');
  protected readonly loading = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly health = signal<HealthResponse | null>(null);

  protected readonly postsLoading = signal(false);
  protected readonly postsError = signal<string | null>(null);
  protected readonly posts = signal<Post[]>([]);
  protected readonly titleInput = signal('');
  protected readonly contentInput = signal('');
  protected readonly creatingPost = signal(false);
  protected readonly createPostError = signal<string | null>(null);

  private readonly apiBaseUrl = this.resolveApiBaseUrl();

  constructor(private readonly http: HttpClient) {
    this.checkHealth();
    this.loadPosts();
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

  protected onTitleChange(value: string): void {
    this.titleInput.set(value);
  }

  protected onContentChange(value: string): void {
    this.contentInput.set(value);
  }

  protected loadPosts(): void {
    this.postsLoading.set(true);
    this.postsError.set(null);

    this.http.get<Post[]>(`${this.apiBaseUrl}/posts`).subscribe({
      next: (response) => {
        this.posts.set(response ?? []);
        this.postsLoading.set(false);
      },
      error: (err) => {
        const message = err?.error?.message || err?.message || 'Failed to load posts.';
        this.postsError.set(message);
        this.postsLoading.set(false);
      }
    });
  }

  protected createPost(): void {
    const title = this.titleInput().trim();
    const content = this.contentInput().trim();

    if (!title || !content) {
      this.createPostError.set('Title and content are required.');
      return;
    }

    this.creatingPost.set(true);
    this.createPostError.set(null);

    this.http.post<Post>(`${this.apiBaseUrl}/posts`, { title, content }).subscribe({
      next: (response) => {
        this.posts.set([response, ...this.posts()]);
        this.titleInput.set('');
        this.contentInput.set('');
        this.creatingPost.set(false);
      },
      error: (err) => {
        const message = err?.error?.message || err?.message || 'Failed to create post.';
        this.createPostError.set(message);
        this.creatingPost.set(false);
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

  private resolveApiBaseUrl(): string {
    const runtimeApi = window.__APP_CONFIG__?.apiBaseUrl?.trim();
    if (runtimeApi) {
      return runtimeApi.replace(/\/$/, '');
    }

    return 'http://localhost:8080';
  }
}
