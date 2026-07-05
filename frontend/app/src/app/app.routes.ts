import { Routes } from '@angular/router';
import { AdminPostsComponent } from './pages/admin-posts.component';
import { PostViewComponent } from './pages/post-view.component';

export const routes: Routes = [
	{
		path: '',
		component: PostViewComponent
	},
	{
		path: 'admin',
		component: AdminPostsComponent
	},
	{
		path: '**',
		redirectTo: ''
	}
];
