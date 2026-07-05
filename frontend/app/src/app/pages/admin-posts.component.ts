import { Component, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';

type Post = {
  id: number;
  title: string;
  content: string;
  imageUrl?: string | null;
  createdAt: string;
  updatedAt?: string | null;
};

type UploadResponse = {
  key: string;
  imageUrl: string;
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
  selector: 'app-admin-posts-page',
  standalone: true,
  templateUrl: './admin-posts.component.html',
  styleUrl: './admin-posts.component.scss'
})
export class AdminPostsComponent {
  protected readonly loading = signal(false);
  protected readonly error = signal<string | null>(null);
  protected readonly posts = signal<Post[]>([]);

  protected readonly titleInput = signal('');
  protected readonly contentInput = signal('');
  protected readonly imageUrlInput = signal('');
  protected readonly creating = signal(false);
  protected readonly createError = signal<string | null>(null);

  protected readonly editId = signal<number | null>(null);
  protected readonly editTitle = signal('');
  protected readonly editContent = signal('');
  protected readonly editImageUrl = signal('');
  protected readonly savingEdit = signal(false);
  protected readonly editError = signal<string | null>(null);

  private selectedCreateFile: File | null = null;
  private selectedEditFile: File | null = null;

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

  protected onCreateTitle(value: string): void {
    this.titleInput.set(value);
  }

  protected onCreateContent(value: string): void {
    this.contentInput.set(value);
  }

  protected onCreateImageUrl(value: string): void {
    this.imageUrlInput.set(value);
  }

  protected onCreateFile(event: Event): void {
    const target = event.target as HTMLInputElement;
    this.selectedCreateFile = target.files && target.files.length > 0 ? target.files[0] : null;
  }

  protected async createPost(): Promise<void> {
    const title = this.titleInput().trim();
    const content = this.contentInput().trim();

    if (!title || !content) {
      this.createError.set('Title and content are required.');
      return;
    }

    this.createError.set(null);
    this.creating.set(true);

    try {
      let imageUrl = this.imageUrlInput().trim();
      if (this.selectedCreateFile) {
        imageUrl = await this.uploadImage(this.selectedCreateFile);
      }

      const created = await firstValueFrom(
        this.http.post<Post>(`${this.apiBaseUrl}/posts`, {
          title,
          content,
          imageUrl: imageUrl || null
        })
      );

      this.posts.set([created, ...this.posts()]);
      this.titleInput.set('');
      this.contentInput.set('');
      this.imageUrlInput.set('');
      this.selectedCreateFile = null;
    } catch (err: any) {
      const message = err?.error?.message || err?.message || 'Failed to create post.';
      this.createError.set(message);
    } finally {
      this.creating.set(false);
    }
  }

  protected startEdit(post: Post): void {
    this.editId.set(post.id);
    this.editTitle.set(post.title);
    this.editContent.set(post.content);
    this.editImageUrl.set(post.imageUrl || '');
    this.editError.set(null);
    this.selectedEditFile = null;
  }

  protected cancelEdit(): void {
    this.editId.set(null);
    this.editTitle.set('');
    this.editContent.set('');
    this.editImageUrl.set('');
    this.selectedEditFile = null;
    this.editError.set(null);
  }

  protected onEditTitle(value: string): void {
    this.editTitle.set(value);
  }

  protected onEditContent(value: string): void {
    this.editContent.set(value);
  }

  protected onEditImageUrl(value: string): void {
    this.editImageUrl.set(value);
  }

  protected onEditFile(event: Event): void {
    const target = event.target as HTMLInputElement;
    this.selectedEditFile = target.files && target.files.length > 0 ? target.files[0] : null;
  }

  protected async saveEdit(): Promise<void> {
    const id = this.editId();
    if (id === null) {
      return;
    }

    const title = this.editTitle().trim();
    const content = this.editContent().trim();

    if (!title || !content) {
      this.editError.set('Title and content are required.');
      return;
    }

    this.savingEdit.set(true);
    this.editError.set(null);

    try {
      let imageUrl = this.editImageUrl().trim();
      if (this.selectedEditFile) {
        imageUrl = await this.uploadImage(this.selectedEditFile);
      }

      const updated = await firstValueFrom(
        this.http.put<Post>(`${this.apiBaseUrl}/posts/${id}`, {
          title,
          content,
          imageUrl: imageUrl || null
        })
      );

      this.posts.set(this.posts().map(post => (post.id === id ? updated : post)));
      this.cancelEdit();
    } catch (err: any) {
      const message = err?.error?.message || err?.message || 'Failed to update post.';
      this.editError.set(message);
    } finally {
      this.savingEdit.set(false);
    }
  }

  protected async deletePost(id: number): Promise<void> {
    if (!confirm('Delete this post?')) {
      return;
    }

    try {
      await firstValueFrom(this.http.delete<void>(`${this.apiBaseUrl}/posts/${id}`));
      this.posts.set(this.posts().filter(post => post.id !== id));
    } catch (err: any) {
      const message = err?.error?.message || err?.message || 'Failed to delete post.';
      this.error.set(message);
    }
  }

  protected formatUtc(value: string): string {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      return value;
    }

    return date.toLocaleString();
  }

  private async uploadImage(file: File): Promise<string> {
    const formData = new FormData();
    formData.append('file', file);

    const response = await firstValueFrom(
      this.http.post<UploadResponse>(`${this.apiBaseUrl}/admin/uploads`, formData)
    );

    return response.imageUrl;
  }
}

function resolveApiBaseUrl(): string {
  const runtimeApi = window.__APP_CONFIG__?.apiBaseUrl?.trim();
  if (runtimeApi) {
    return runtimeApi.replace(/\/$/, '');
  }

  return 'http://localhost:8080';
}
