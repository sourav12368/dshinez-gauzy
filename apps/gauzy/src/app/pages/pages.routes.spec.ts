import { DOCUMENT } from '@angular/common';
import { Injector, runInInjectionContext } from '@angular/core';
import { ActivatedRouteSnapshot, CanActivateFn, Router, RouterStateSnapshot } from '@angular/router';
import { RolesEnum } from '@gauzy/contracts';
import { RESERVED_PAGE_SECTION_PATHS, UsersService } from '@gauzy/ui-core/core';
import { getPagesRoutes } from './pages.routes';
/**
 * Asserts that RESERVED_PAGE_SECTION_PATHS stays in sync with the core route
 * paths from getPagesRoutes(). Prevents adding new core routes without updating
 * the reserved set (which would allow plugins to register conflicting paths).
 */
describe('pages.routes', () => {
	it.each([
		[RolesEnum.EMPLOYEE, 'work.dshinez.com', '/pages/tasks/me'],
		[RolesEnum.MANAGER, 'work.dshinez.com', '/pages/tasks/team'],
		[RolesEnum.ADMIN, 'work.dshinez.com', '/pages/tasks/dashboard'],
		[RolesEnum.SUPER_ADMIN, 'work.dshinez.com', '/pages/tasks/dashboard'],
		[RolesEnum.VIEWER, 'work.dshinez.com', '/pages/dashboard'],
		[RolesEnum.EMPLOYEE, 'localhost', '/pages/dashboard']
	])('opens the appropriate view for %s on %s', async (role, hostname, destination) => {
		const registry = { getPageLocationRoutes: () => [] } as Parameters<typeof getPagesRoutes>[0];
		const entry = getPagesRoutes(registry)[0].children?.find(({ path }) => path === '');
		const guard = entry?.canActivate?.[0] as CanActivateFn;
		const getMe = jest.fn().mockResolvedValue({ tenantId: 'tenant', role: { name: role } });
		const createUrlTree = jest.fn().mockImplementation(([path]) => path);
		const injector = Injector.create({
			providers: [
				{ provide: DOCUMENT, useValue: { location: { hostname } } },
				{ provide: UsersService, useValue: { getMe } },
				{ provide: Router, useValue: { createUrlTree } }
			]
		});

		await expect(
			runInInjectionContext(injector, () => guard({} as ActivatedRouteSnapshot, {} as RouterStateSnapshot))
		).resolves.toBe(destination);
		if (hostname === 'work.dshinez.com') {
			expect(getMe).toHaveBeenCalledWith(['role']);
		} else {
			expect(getMe).not.toHaveBeenCalled();
		}
	});

	it('RESERVED_PAGE_SECTION_PATHS matches core top-level paths from getPagesRoutes()', () => {
		const mockRegistry = {
			getPageLocationRoutes: () => []
		} as any;
		const routes = getPagesRoutes(mockRegistry);
		const parent = routes[0];
		const children = parent?.children ?? [];
		const corePaths = new Set<string>(
			children.map((r) => r.path).filter((p): p is string => typeof p === 'string' && p !== '' && p !== '**')
		);
		const reserved = RESERVED_PAGE_SECTION_PATHS;
		const missing = [...reserved].filter((p) => !corePaths.has(p));
		const extra = [...corePaths].filter((p) => !reserved.has(p));
		if (missing.length > 0) {
			throw new Error(
				`Missing reserved paths (in RESERVED_PAGE_SECTION_PATHS but not in getPagesRoutes()): ${missing.join(', ')}. ` +
					`Update getPagesRoutes() or remove from RESERVED_PAGE_SECTION_PATHS.`
			);
		}
		if (extra.length > 0) {
			throw new Error(
				`Unexpected core paths (in getPagesRoutes() but not in RESERVED_PAGE_SECTION_PATHS): ${extra.join(', ')}. ` +
					`Add these to RESERVED_PAGE_SECTION_PATHS to prevent plugin path conflicts.`
			);
		}
	});
});
