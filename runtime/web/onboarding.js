const steps = [...document.querySelectorAll('main > section')];
const back = document.querySelector('#back');
const next = document.querySelector('#next');
let current = 0;
function show(step, focus = false) {
	current = step;
	steps.forEach((section, index) => { section.hidden = index !== step; });
	document.querySelector('#step-number').textContent = 'Step ' + (step + 1) + ' of ' + steps.length;
	back.disabled = step === 0;
	next.textContent = step === steps.length - 1 ? 'Open Gauzy' : 'Next';
	if (focus) steps[step].querySelector('h2').focus();
}
back.addEventListener('click', () => show(current - 1, true));
next.addEventListener('click', () => {
	if (current === steps.length - 1) window.location.href = '/';
	else show(current + 1, true);
});
document.querySelector('nav').hidden = false;
show(0);
