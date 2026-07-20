using System.Collections.Generic;
using UnityEngine;

namespace PixelSkin
{
    /// <summary>
    /// 1キャラクターが持つスキンバリエーションのリスト（決定9/10）。
    /// skins のインデックスが CharacterSkinController.SetSkin(index) の引数（決定22）。
    /// </summary>
    [CreateAssetMenu(menuName = "PixelSkin/Character Skin Library", fileName = "CharacterSkinLibrary")]
    public class CharacterSkinLibrary : ScriptableObject
    {
        public string characterId;
        public List<SkinSet> skins = new List<SkinSet>();
    }
}
