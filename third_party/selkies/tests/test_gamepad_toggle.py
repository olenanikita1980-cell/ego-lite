import os
import sys
import tempfile
import unittest


SELKIES_SRC = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "src"))
sys.path.insert(0, SELKIES_SRC)

from selkies import input_handler


class GamepadToggleTest(unittest.IsolatedAsyncioTestCase):
    async def test_disabled_gamepads_do_not_initialize_persistent_sockets(self):
        original_setting = input_handler.settings.gamepad_enabled
        original_gamepad = input_handler.SelkiesGamepad
        original_persistent = dict(input_handler._persistent_gamepads)
        created = []

        class FakeGamepad:
            def __init__(self, js_path, evdev_path, loop):
                created.append((js_path, evdev_path))

            def set_config(self, *_args):
                pass

            async def run_servers(self):
                pass

        try:
            input_handler.settings.gamepad_enabled = (False, False)
            input_handler.SelkiesGamepad = FakeGamepad
            input_handler._persistent_gamepads.clear()

            with tempfile.TemporaryDirectory() as temp_dir:
                socket_dir = os.path.join(temp_dir, "gamepads")
                handler = object.__new__(input_handler.WebRTCInput)
                handler.num_gamepads = 4
                handler.gamepad_instances = {}
                handler.js_socket_path_prefix = socket_dir
                handler.loop = None
                handler._spawn_task = lambda coro: coro.close()

                await handler._initialize_persistent_gamepads()

                self.assertEqual(created, [])
                self.assertEqual(handler.gamepad_instances, {})
                self.assertFalse(os.path.exists(socket_dir))
        finally:
            input_handler.settings.gamepad_enabled = original_setting
            input_handler.SelkiesGamepad = original_gamepad
            input_handler._persistent_gamepads.clear()
            input_handler._persistent_gamepads.update(original_persistent)


if __name__ == "__main__":
    unittest.main()
