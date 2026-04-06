#!/usr/bin/env python3
#
# ASKA Dedicated Server Manager
# Manages the ASKA game server as a systemd service via Warlock.
#
# @LICENSE AGPLv3
# @AUTHOR  Charlie Powell <cdp1337@bitsnbytes.dev>
#
import os
import sys

# Include the virtual environment site-packages in sys.path
here = os.path.dirname(os.path.realpath(__file__))
if not os.path.exists(os.path.join(here, '.venv')):
	print('Python environment not setup')
	exit(1)
sys.path.insert(
	0,
	os.path.join(
		here,
		'.venv',
		'lib',
		'python' + '.'.join(sys.version.split('.')[:2]), 'site-packages'
	)
)

import logging
import pwd
import time
from warlock_manager.apps.steam_app import SteamApp, guess_steamcmd_path
from warlock_manager.services.base_service import BaseService
from warlock_manager.config.ini_config import INIConfig
from warlock_manager.config.properties_config import PropertiesConfig
from warlock_manager.libs.app_runner import app_runner
from warlock_manager.libs.firewall import Firewall
from warlock_manager.libs import utils
from warlock_manager.libs.cmd import Cmd


class GameApp(SteamApp):
	"""
	ASKA game application manager.

	ASKA ships only as a Windows binary (AskaServer.exe) and runs on Linux
	via Wine + Xvfb. The SteamCMD Windows platform flag is required to
	download the correct depot.
	"""

	def __init__(self):
		super().__init__()

		self.name = 'aska'
		self.desc = 'ASKA Dedicated Server'
		self.steam_id = '3246670'
		self.service_handler = GameService
		self.service_prefix = 'aska-'
		# ASKA has a single shared config file; multiple instances would conflict.
		# No in-game console or mod support.
		self.disabled_features = {'create_service', 'cmd', 'mods'}

		self.configs = {
			'manager': INIConfig('manager', os.path.join(utils.get_app_directory(), '.settings.ini'))
		}
		self.load()

	def first_run(self) -> bool:
		if os.geteuid() != 0:
			logging.error('Please run this script with sudo to perform first-run configuration.')
			return False

		super().first_run()

		# Download ASKA server files via SteamCMD (Windows depot)
		self.update()

		# Create the Wine prefix directory; Wine initializes it on first launch.
		wineprefix_dir = os.path.join(utils.get_app_directory(), 'wineprefix')
		if not os.path.exists(wineprefix_dir):
			os.makedirs(wineprefix_dir)
			game_uid = pwd.getpwnam(utils.get_app_uid()).pw_uid
			os.chown(wineprefix_dir, game_uid, game_uid)

		# SteamCMD ships a server properties.txt in AppFiles with the correct format.
		# Only create a fallback if it was somehow absent after download.
		props_path = os.path.join(utils.get_app_directory(), 'AppFiles', 'server properties.txt')
		if not os.path.exists(props_path):
			self._create_default_properties(props_path)

		services = self.get_services()
		if len(services) == 0:
			logging.info('No services detected, creating one...')
			self.create_service('aska-server')
		else:
			logging.info('Detected %d services, skipping first-run service creation.' % len(services))

		return True

	def update(self):
		"""
		Override SteamApp.update() to inject +@sSteamCmdForcePlatformType windows.

		ASKA has no native Linux binary. Without this flag, SteamCMD would attempt
		to download the (non-existent) Linux depot and fail.

		The flag must appear before +app_update in the argument list.
		"""
		logging.info('Updating %s via Steam (Windows depot)...' % self.name)
		services = []
		for service in self.get_services():
			if service.is_running() or service.is_starting():
				logging.info('Stopping service %s for update...' % service.service)
				services.append(service)
				service.stop()

		if len(services) > 0:
			logging.info('Waiting up to 5 minutes for all services to stop...')
			counter = 0
			while counter < 30:
				all_stopped = True
				counter += 1
				for service in self.get_services():
					if service.is_running() or service.is_starting() or service.is_stopping():
						all_stopped = False
						break
				if all_stopped:
					break
				time.sleep(10)
		else:
			logging.info('No running services found, proceeding with update...')

		cmd = Cmd([
			guess_steamcmd_path(),
			'+@sSteamCmdForcePlatformType', 'windows',
			'+@sSteamCmdForcePlatformBitness', '64',
			'+force_install_dir',
			os.path.join(self.get_app_directory(), 'AppFiles'),
			'+login',
			'anonymous',
			'+app_update',
			self.steam_id,
		])
		cmd.sudo(utils.get_app_uid())
		cmd.stream_output()
		cmd.append('validate')
		cmd.append('+quit')
		cmd.run()

		self.post_update()

		if len(services) > 0:
			logging.info('Update completed, restarting previously running services...')
			for service in services:
				service.start()
				time.sleep(10)

		return cmd.success

	def _create_default_properties(self, path: str):
		"""Write a minimal default server properties file in ASKA's native format."""
		content = (
			'display name = Default Session\n'
			'server name = My ASKA Server\n'
			'save id =\n'
			'password =\n'
			'steam game port = 27015\n'
			'steam query port = 27016\n'
			'authentication token =\n'
			'region = default\n'
			'keep server world alive = false\n'
			'autosave style = every morning\n'
		)
		with open(path, 'w') as f:
			f.write(content)
		utils.ensure_file_ownership(path)


class GameService(BaseService):
	"""
	ASKA service instance manager.

	Runs AskaServer.exe via Wine under a virtual display (xvfb-run).
	ASKA has no RCON or HTTP API, so player count is unavailable.
	"""

	def __init__(self, service: str, game: GameApp):
		super().__init__(service, game)
		# The properties file lives inside AppFiles, which is the WorkingDirectory
		# for the service. self.get_app_directory() returns that AppFiles path.
		self.configs = {
			'game': PropertiesConfig('game', os.path.join(self.get_app_directory(), 'server properties.txt'))
		}
		self.load()

	def get_executable(self) -> str:
		"""
		Return the ExecStart string for the systemd unit.

		xvfb-run is required because Wine's background subsystem (explorer.exe etc.)
		still attempts to create windows even in -nographics mode.

		Both the exe and -propertiesPath are relative to WorkingDirectory (AppFiles),
		matching the layout the shipped AskaServer.bat uses.
		"""
		return (
			'xvfb-run -a wine AskaServer.exe'
			' -nographics -batchmode'
			' -propertiesPath "server properties.txt"'
		)

	def get_environment(self) -> dict:
		"""Return the env vars required by Wine."""
		wineprefix_dir = os.path.join(utils.get_app_directory(), 'wineprefix')
		return {
			'WINEPREFIX': wineprefix_dir,
			'WINEARCH': 'win64',
			'WINEDEBUG': '-all',
		}

	def is_api_enabled(self) -> bool:
		return False

	def get_player_count(self) -> int | None:
		# ASKA has no queryable API; return None (unknown) rather than 0 (empty).
		return None

	def get_port(self) -> int | None:
		return self.get_option_value('steam game port')

	def get_game_pid(self) -> int:
		"""
		The systemd MainPID is xvfb-run. Walk its child processes to find
		the wine process for accurate memory/CPU metric reporting.
		"""
		pid = self.get_pid()
		if pid == 0:
			return 0
		try:
			import subprocess
			result = subprocess.run(
				['pgrep', '-P', str(pid), '-f', 'wine'],
				stdout=subprocess.PIPE,
				stderr=subprocess.PIPE,
				timeout=5
			)
			for line in result.stdout.decode().strip().split('\n'):
				if line.strip().isdigit():
					return int(line.strip())
		except Exception:
			pass
		return pid

	def get_name(self) -> str:
		return self.get_option_value('server name')

	def get_port_definitions(self) -> list:
		return [
			('steam game port', 'udp', '%s game port' % self.game.name),
			('steam query port', 'udp', '%s Steam query port' % self.game.name),
		]

	def option_value_updated(self, option: str, previous_value, new_value):
		if option == 'steam game port':
			if previous_value:
				Firewall.remove(int(previous_value), 'udp')
			Firewall.allow(int(new_value), 'udp', '%s game port' % self.game.desc)
		elif option == 'steam query port':
			if previous_value:
				Firewall.remove(int(previous_value), 'udp')
			Firewall.allow(int(new_value), 'udp', '%s Steam query port' % self.game.desc)

	def create_service(self):
		super().create_service()
		self.set_option('server name', 'My ASKA Server')


if __name__ == '__main__':
	app = app_runner(GameApp())
	app()
