import { RolesEnum } from '@gauzy/contracts';
import { NgxLoginComponent } from './login.component';

describe('D’Shinez employee login mode', () => {
	function createLogin(branded: boolean): NgxLoginComponent {
		// Exercise only the portal-mode logic; no real login service or credentials are needed.
		const component = Object.create(NgxLoginComponent.prototype) as NgxLoginComponent;
		Object.assign(component, {
			isDshinez: false,
			isDemo: true,
			el: {
				nativeElement: {
					closest: () => ({
						classList: { contains: (name: string) => name === 'dshinez-app' && branded },
						removeAttribute: jest.fn()
					})
				}
			}
		});
		jest.spyOn(component, 'checkRememberdMe').mockImplementation();
		jest.spyOn(component, 'autoFillCredential').mockImplementation();
		return component;
	}

	it('disables demo autofill on the D’Shinez employee portal', () => {
		const component = createLogin(true);
		component.ngOnInit();

		expect(component.isDshinez).toBe(true);
		expect(component.autoFillCredential).not.toHaveBeenCalled();
		// Even if a stale UI event invokes a demo action, it must never auto-submit.
		expect(() => component.autoLogin(RolesEnum.EMPLOYEE)).not.toThrow();
		expect(component.autoFillCredential).not.toHaveBeenCalled();
	});

	it('preserves normal Gauzy demo behavior outside D’Shinez', () => {
		const component = createLogin(false);
		component.ngOnInit();

		expect(component.isDshinez).toBe(false);
		expect(component.autoFillCredential).toHaveBeenCalledTimes(1);
	});
});
