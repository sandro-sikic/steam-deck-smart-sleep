import { act, fireEvent, render, screen, within } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import App from './App';
import {
	INSTALL_COMMAND,
	UNINSTALL_COMMAND,
	UNINSTALL_OFFLINE_COMMAND,
} from './commands';

const writeText = vi.fn().mockResolvedValue(undefined);

beforeEach(() => {
	writeText.mockClear();
	Object.defineProperty(navigator, 'clipboard', {
		value: { writeText },
		configurable: true,
	});
});

describe('commands', () => {
	it('point at the install and uninstall scripts on main', () => {
		expect(INSTALL_COMMAND).toBe(
			'curl -fsSL https://raw.githubusercontent.com/sandro-sikic/steam-deck-smart-sleep/main/install.sh | sudo bash',
		);
		expect(UNINSTALL_COMMAND).toBe(
			'curl -fsSL https://raw.githubusercontent.com/sandro-sikic/steam-deck-smart-sleep/main/uninstall.sh | sudo bash',
		);
		expect(UNINSTALL_OFFLINE_COMMAND).toBe(
			'sudo ~/steam-deck-smart-sleep/uninstall.sh',
		);
	});
});

describe('App', () => {
	it('keeps the existing install box', () => {
		render(<App />);
		expect(screen.getByText('Quick Install')).toBeInTheDocument();
		expect(screen.getByText(INSTALL_COMMAND)).toBeInTheDocument();
		expect(
			screen.getByRole('link', { name: /view on github/i }),
		).toHaveAttribute(
			'href',
			'https://github.com/sandro-sikic/steam-deck-smart-sleep',
		);
	});

	it('explains how to uninstall, online and offline', () => {
		render(<App />);
		expect(screen.getByText('Uninstall')).toBeInTheDocument();
		expect(screen.getByText(UNINSTALL_COMMAND)).toBeInTheDocument();
		expect(screen.getByText(UNINSTALL_OFFLINE_COMMAND)).toBeInTheDocument();
		expect(screen.getByText(/no internet\? use the local copy/i)).toBeVisible();
		expect(screen.getByText('Removes:')).toBeInTheDocument();
		expect(screen.getByText('Keeps:')).toBeInTheDocument();
		expect(screen.getByText('~/steam-deck-smart-sleep')).toBeInTheDocument();
	});

	it('copies the right command from each box independently', async () => {
		render(<App />);
		const [installCopy, uninstallCopy] = screen.getAllByRole('button', {
			name: /copy/i,
		});

		await act(async () => {
			fireEvent.click(uninstallCopy);
		});
		expect(writeText).toHaveBeenLastCalledWith(UNINSTALL_COMMAND);
		expect(uninstallCopy).toHaveTextContent('Copied!');
		expect(installCopy).not.toHaveTextContent('Copied!');

		await act(async () => {
			fireEvent.click(installCopy);
		});
		expect(writeText).toHaveBeenLastCalledWith(INSTALL_COMMAND);
	});

	it('keeps the security notice above the commands', () => {
		render(<App />);
		const notice = screen.getByText('Security Notice:').closest('div')!;
		expect(
			within(notice).getByRole('link', { name: /verify the source code/i }),
		).toBeInTheDocument();
	});
});
