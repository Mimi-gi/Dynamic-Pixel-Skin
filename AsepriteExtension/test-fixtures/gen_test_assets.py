"""テスト用の DirectionalSkin / DirectionalAnimation を生成する（手描き不要）。
Aseprite での実機ベイク検証に使う。生成物:
  test_skin.png  ... 4x4、各ピクセル一意色（= 座標辞書の元）
  test_anim.png  ... 4x4、skin色を既知の位置に配置（残りは透明）

ベイク後の期待値（skin_height=4, exact モード）:
  R = 元スキンX,  G = (4-1) - 元スキンY
"""
import os
import mini_png

HERE = os.path.dirname(os.path.abspath(__file__))

SKIN_W = SKIN_H = 4


def skin_color(x, y):
    # x,y in 0..3 -> 一意なRGB。r,g が {20,60,100,140} でユニーク。
    return (20 + 40 * x, 20 + 40 * y, 100, 255)


def gen_skin():
    pix = [skin_color(x, y) for y in range(SKIN_H) for x in range(SKIN_W)]
    mini_png.write_rgba(os.path.join(HERE, "test_skin.png"), SKIN_W, SKIN_H, pix)


# アニメ配置: anim座標(ax,ay) -> 参照するskin座標(sx,sy)
PLACEMENTS = {
    (0, 0): (2, 0),
    (3, 0): (0, 3),
    (1, 2): (3, 1),
    (2, 3): (1, 3),
}

ANIM_W = ANIM_H = 4
TRANSPARENT = (0, 0, 0, 0)


def gen_anim():
    pix = [TRANSPARENT] * (ANIM_W * ANIM_H)
    for (ax, ay), (sx, sy) in PLACEMENTS.items():
        pix[ay * ANIM_W + ax] = skin_color(sx, sy)
    mini_png.write_rgba(os.path.join(HERE, "test_anim.png"), ANIM_W, ANIM_H, pix)


def expected_output():
    """out.png の期待ピクセル {(x,y): (r,g,b,a)}。他は透明。"""
    exp = {}
    for (ax, ay), (sx, sy) in PLACEMENTS.items():
        exp[(ax, ay)] = (sx, (SKIN_H - 1) - sy, 0, 255)
    return exp


if __name__ == "__main__":
    gen_skin()
    gen_anim()
    print("生成: test_skin.png (4x4), test_anim.png (4x4)")
    print("期待出力(out.png, 4x4):")
    for (x, y), c in sorted(expected_output().items()):
        print("  (%d,%d) -> R=%d G=%d A=%d" % (x, y, c[0], c[1], c[3]))
    print("  それ以外のピクセル -> A=0（透明）")
