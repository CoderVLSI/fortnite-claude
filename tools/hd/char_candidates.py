#!/usr/bin/env python3
"""Collects Sketchfab candidates (animated = rigged, CC0 / CC-BY, small) for every skin -> tools/hd/characters.json
{skin: [{uid, name, author, faces}]}. Third-party franchise characters are skipped by name."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sketchfab
BAD = ("fortnite", "epic", "spider", "master chief", "halo", "nazi", "kung fu", "among us", "pubg", "mario", "pokemon", "tmnt", "turtles",
       "minecraft", "sonic", "zelda", "naruto", "goku", "batman", "superman", "marvel", "disney", "pixar", "lego", "roblox", "overwatch", "valorant",
       "apex", "call of duty", "cod ", "terrorist", "gwen", "avengers", "star wars", "mandalorian", "fnaf", "five nights", "nijisanji", "vtuber", "naked", "nude", "sexy")
QUERIES = {
    "ranger": ["soldier low poly", "adventurer character", "explorer character"],
    "ninja": ["ninja", "assassin character", "shinobi"],
    "astronaut": ["astronaut character", "spaceman rigged", "cosmonaut"],
    "knight": ["knight", "armored knight rigged", "medieval knight"],
    "robot": ["humanoid robot rigged", "robot character", "android"],
    "pirate": ["pirate character", "pirate captain", "buccaneer"],
    "cowboy": ["cowboy", "western gunslinger", "sheriff character"],
    "dino": ["dinosaur costume", "dino character humanoid", "trex mascot"],
    "banana": ["banana man", "fruit character", "banana mascot"],
    "fishhead": ["fish man humanoid", "merman", "fish mascot"],
    "marine": ["marine soldier", "military soldier rigged", "commando"],
    "wristhero": ["boy hero", "kid superhero", "teen hero rigged"],
    "pumpkin": ["pumpkin head", "scarecrow", "halloween character"],
    "shark": ["shark man", "shark mascot", "shark character"],
    "panda": ["panda mascot", "panda costume", "bear mascot"],
    "viking": ["viking", "barbarian warrior", "norse warrior"],
    "chef": ["chef character", "cook character", "baker character"],
    "cactus": ["cactus character", "cactus man", "desert character"],
    "chicken": ["chicken mascot", "chicken costume", "bird mascot"],
    "ranger_f": ["female soldier rigged", "woman adventurer", "female ranger"],
    "aviator": ["pilot character", "aviator", "aviator goggles"],
    "scientist": ["scientist character", "lab coat character", "doctor character"],
    "witch": ["witch", "sorceress", "wizard girl"],
    "pigtails": ["girl pigtails", "kid girl rigged", "schoolgirl character"],
    "princess": ["princess", "queen character", "fantasy lady"],
    "soccer": ["soccer player", "football player rigged", "sports player"],
    "bunny": ["bunny girl", "rabbit character humanoid", "bunny mascot"],
    "rodeo": ["cowgirl", "rodeo rider", "western woman"],
    "piratequeen": ["female pirate", "pirate woman", "pirate girl"],
    "shieldmaiden": ["shieldmaiden", "female viking", "female warrior"],
    "chefbella": ["female chef", "woman cook", "chef girl"],
    "astroada": ["female astronaut", "woman astronaut", "astronaut girl"],
    "dame": ["lady character", "woman rigged", "elegant lady"],
    "goldie": ["girl character rigged", "kid girl", "young girl"],
}
out = {}
for skin, qs in QUERIES.items():
    seen = {}
    for q in qs:
        try:
            for m in sketchfab.search(q, max_faces=25000, licenses=("cc0", "by"), count=6, animated=True):
                nm = m["name"].lower()
                if any(b in nm for b in BAD) or m["uid"] in seen:
                    continue
                seen[m["uid"]] = m
        except Exception as e:
            print("search failed", q, e)
        time.sleep(0.2)
    out[skin] = list(seen.values())[:8]
    print(skin, len(out[skin]))
json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "characters.json"), "w"), indent=1)
