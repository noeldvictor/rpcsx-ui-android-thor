#!/usr/bin/env python3
"""Test the Transformers START-frame classifier."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

from PIL import Image, ImageDraw


SCRIPT_PATH = Path(__file__).parent / "bench" / "thor_transformers_start_check.py"
SPEC = importlib.util.spec_from_file_location("thor_transformers_start_check", SCRIPT_PATH)
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class TransformersStartCheckTests(unittest.TestCase):
    def score_image(self, draw_image):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frame.png"
            image = Image.new("RGB", (1920, 1080), "black")
            draw_image(image)
            image.save(path)
            return CHECK.score(path)

    def test_large_legal_text_area_is_ready(self):
        def draw(image):
            canvas = ImageDraw.Draw(image)
            canvas.rectangle((154, 562, 1766, 735), fill=(230, 230, 230))

        self.assertTrue(self.score_image(draw)["startReady"])

    def test_small_loading_symbol_is_not_ready(self):
        def draw(image):
            canvas = ImageDraw.Draw(image)
            canvas.ellipse((1535, 790, 1680, 935), outline=(255, 255, 255), width=18)

        self.assertFalse(self.score_image(draw)["startReady"])

    def test_compile_background_is_not_ready(self):
        def draw(image):
            canvas = ImageDraw.Draw(image)
            canvas.rectangle((0, 0, 1919, 1079), fill=(12, 31, 55))
            canvas.rectangle((360, 660, 1559, 666), fill=(240, 240, 240))

        self.assertFalse(self.score_image(draw)["startReady"])


if __name__ == "__main__":
    unittest.main()
