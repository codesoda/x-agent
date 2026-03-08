import unittest

from src.app import greet


class TestApp(unittest.TestCase):
    def test_greet_fails(self):
        self.assertEqual(greet("world"), "Wrong answer!")


if __name__ == "__main__":
    unittest.main()
