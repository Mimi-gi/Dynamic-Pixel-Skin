"""Aseprite でベイクした out.png を検証する。
使い方:  python check_output.py <out.png へのパス>

test_anim.png を test_skin.png でベイクした結果が、期待する rg エンコード
（R=元スキンX, G=(スキン高さ-1)-元スキンY, 透明処理）になっているか自動判定する。
"""
import sys
import os
import mini_png
import gen_test_assets as g


def main(path):
    if not os.path.exists(path):
        print("ファイルが見つかりません: %s" % path)
        return 2
    w, h, pix = mini_png.read(path)
    print("読み込み: %s  (%dx%d)" % (path, w, h))

    if (w, h) != (g.ANIM_W, g.ANIM_H):
        print("  注意: サイズが期待(%dx%d)と異なります。1フレーム=%dx%d を想定。"
              % (g.ANIM_W, g.ANIM_H, g.ANIM_W, g.ANIM_H))

    exp = g.expected_output()
    passed = failed = 0

    def px(x, y):
        return pix[y * w + x]

    # 期待する有効ピクセル
    for (x, y), c in sorted(exp.items()):
        got = px(x, y)
        # R,G,A を検証（Bは0想定だが厳密比較しない）
        ok = (got[0] == c[0] and got[1] == c[1] and got[3] == c[3])
        print("  %s (%d,%d): 期待 R=%d G=%d A=%d / 実際 R=%d G=%d B=%d A=%d"
              % ("PASS" if ok else "FAIL", x, y, c[0], c[1], c[3],
                 got[0], got[1], got[2], got[3]))
        passed += ok
        failed += (not ok)

    # それ以外は透明であること
    stray = 0
    for y in range(min(h, g.ANIM_H)):
        for x in range(min(w, g.ANIM_W)):
            if (x, y) in exp:
                continue
            if px(x, y)[3] != 0:
                stray += 1
                if stray <= 5:
                    print("  FAIL 透明のはずが不透明: (%d,%d) A=%d" % (x, y, px(x, y)[3]))
    if stray == 0:
        print("  PASS: 期待位置以外はすべて透明")
        passed += 1
    else:
        print("  FAIL: 想定外の不透明ピクセルが %d 個" % stray)
        failed += 1

    print()
    print("RESULT: %d passed, %d failed" % (passed, failed))
    if failed == 0:
        print("=> ベイクの色エンコードと Yフリップは仕様どおりです。")
        print("   次は Unity にこの out.png を取り込み、意図した向きでサンプリングされるか確認してください。")
    else:
        print("=> 不一致あり。特に G の値が上下で反転している場合は Yフリップの向きを疑ってください。")
    return 1 if failed else 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("使い方: python check_output.py <out.png>")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
