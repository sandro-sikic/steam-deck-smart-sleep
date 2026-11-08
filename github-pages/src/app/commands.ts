const REPO_RAW =
	'https://raw.githubusercontent.com/sandro-sikic/steam-deck-smart-sleep/main';

export const INSTALL_COMMAND = `curl -fsSL ${REPO_RAW}/install.sh | sudo bash`;
export const INSTALL_MINUTES_COMMAND = `${INSTALL_COMMAND} -s -- --minutes 90`;
export const UNINSTALL_COMMAND = `curl -fsSL ${REPO_RAW}/uninstall.sh | sudo bash`;
export const UNINSTALL_OFFLINE_COMMAND =
	'sudo ~/steam-deck-smart-sleep/uninstall.sh';
