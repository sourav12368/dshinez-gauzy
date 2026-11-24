import { DOCUMENT } from '@angular/common';
import { Type } from '@angular/core';
import { TestBed } from '@angular/core/testing';
import { Router } from '@angular/router';
import { NbAuthModule } from '@nebular/auth';
import { of } from 'rxjs';
import { NoAuthGuard, RegistrationConfigService, registrationEnabledGuard } from '@gauzy/ui-core/core';
import { NgxAuthModule } from './auth.module';
import { createAuthRoutes, dshinezEmployeeOnlyRegistrationGuard } from './auth.routes';
import { NgxForgotPasswordComponent } from './components/forgot-password/forgot-password.component';
import { NgxLoginMagicComponent } from './components/login-magic/login-magic.component';
import { NgxResetPasswordComponent } from './components/reset-password/reset-password.component';

/**
 * #5784 / #7821: on a server whose operator closed public sign-ups, the sign-in pages show no Register link and the
 * register route sends visitors to sign in. With sign-ups open (the default) both stay as they have always been.
 */
describe('Auth pages — registration switch', () => {
	function render(component: Type<unknown>, enabled: boolean): HTMLElement {
		TestBed.configureTestingModule({
			// Declared in NgxAuthModule (not standalone): import it for the template's real scope. NbAuthService comes
			// from NbAuthModule.forRoot(), which the app's root module calls.
			imports: [NgxAuthModule, NbAuthModule.forRoot()],
			providers: [{ provide: RegistrationConfigService, useValue: { registrationEnabled$: of(enabled) } }]
		});
		const fixture = TestBed.createComponent(component);
		fixture.detectChanges();
		return fixture.nativeElement as HTMLElement;
	}

	const registerLink = (page: HTMLElement) => page.querySelector('a[href*="/auth/register"]');

	it.each([
		['the e-mail sign-in page', NgxLoginMagicComponent],
		['the forgot-password page', NgxForgotPasswordComponent],
		['the reset-password page', NgxResetPasswordComponent]
	])('shows the Register link on %s while sign-ups are open', (_page, component) => {
		expect(registerLink(render(component, true))).not.toBeNull();
	});

	it.each([
		['the e-mail sign-in page', NgxLoginMagicComponent],
		['the forgot-password page', NgxForgotPasswordComponent],
		['the reset-password page', NgxResetPasswordComponent]
	])('hides the Register link on %s while sign-ups are closed', (_page, component) => {
		const page = render(component, false);

		expect(registerLink(page)).toBeNull();
		// The way back to sign in stays.
		expect(page.querySelector('a[href*="/auth/login"]')).not.toBeNull();
	});

	it('guards the register route with the registration switch', () => {
		const [shell] = createAuthRoutes({ getPageLocationRoutes: () => [] } as never);
		const register = shell.children?.find((route) => route.path === 'register');

		expect(register?.canActivate).toEqual([
			NoAuthGuard,
			registrationEnabledGuard,
			dshinezEmployeeOnlyRegistrationGuard
		]);
	});

	it('redirects public registration to employee login on the D’Shinez-branded portal', () => {
		const target = { toString: () => '/auth/login' };
		const parseUrl = jest.fn().mockReturnValue(target);
		TestBed.configureTestingModule({
			providers: [
				{ provide: DOCUMENT, useValue: { body: { classList: { contains: () => true } } } },
				{ provide: Router, useValue: { parseUrl } }
			]
		});

		expect(TestBed.runInInjectionContext(() => dshinezEmployeeOnlyRegistrationGuard({} as never, {} as never))).toBe(
			target
		);
		expect(parseUrl).toHaveBeenCalledWith('/auth/login');
	});

	it('preserves public registration outside the D’Shinez portal', () => {
		TestBed.configureTestingModule({
			providers: [{ provide: DOCUMENT, useValue: { body: { classList: { contains: () => false } } } }]
		});

		expect(TestBed.runInInjectionContext(() => dshinezEmployeeOnlyRegistrationGuard({} as never, {} as never))).toBe(
			true
		);
	});
});
