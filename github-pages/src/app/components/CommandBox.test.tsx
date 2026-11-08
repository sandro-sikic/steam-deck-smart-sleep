import { act, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { CommandBox } from './CommandBox';

const writeText = vi.fn().mockResolvedValue(undefined);

beforeEach(() => {
	vi.useFakeTimers();
	writeText.mockClear();
	Object.defineProperty(navigator, 'clipboard', {
		value: { writeText },
		configurable: true,
	});
});

afterEach(() => {
	vi.useRealTimers();
});

const renderBox = (props = {}) =>
	render(
		<CommandBox
			label="Some label"
			description="Some description"
			command="echo hello"
			{...props}
		/>,
	);

describe('CommandBox', () => {
	it('shows the label, description and command', () => {
		renderBox();
		expect(screen.getByText('Some label')).toBeInTheDocument();
		expect(screen.getByText('Some description')).toBeInTheDocument();
		expect(screen.getByText('echo hello')).toBeInTheDocument();
		expect(screen.getByRole('button', { name: /copy/i })).toBeInTheDocument();
	});

	it('copies the command and shows "Copied!" until the timeout', async () => {
		renderBox();
		await act(async () => {
			fireEvent.click(screen.getByRole('button'));
		});
		expect(writeText).toHaveBeenCalledWith('echo hello');
		expect(screen.getByRole('button')).toHaveTextContent('Copied!');

		act(() => {
			vi.advanceTimersByTime(1999);
		});
		expect(screen.getByRole('button')).toHaveTextContent('Copied!');

		act(() => {
			vi.advanceTimersByTime(1);
		});
		expect(screen.getByRole('button')).toHaveTextContent('Copy');
		expect(screen.getByRole('button')).not.toHaveTextContent('Copied!');
	});

	it('uses the blue accent by default', () => {
		renderBox();
		expect(screen.getByText('echo hello')).toHaveClass('text-green-400');
	});

	it('supports the red accent', () => {
		renderBox({ accent: 'red' });
		expect(screen.getByText('echo hello')).toHaveClass('text-rose-300');
	});

	it('renders children below the command', () => {
		renderBox({ children: <p>extra notes</p> });
		expect(screen.getByText('extra notes')).toBeInTheDocument();
	});
});
