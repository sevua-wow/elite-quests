local _, ns = ...

-- DONNÉES FICTIVES uniquement pour prévisualiser l'interface (/eq demo).
-- Les ID sont négatifs pour ne jamais correspondre à une vraie quête.
ns.DemoQuests = {
    [-1]  = { name = "[Démo] Rumeurs au village",    level = 10, zone = "Zone de démo A", continent = "Démo" },
    [-2]  = { name = "[Démo] Le messager disparu",   level = 11, zone = "Zone de démo A", continent = "Démo", pre = { -1 } },
    [-3]  = { name = "[Démo] Preuves dans la mine",  level = 12, zone = "Zone de démo A", continent = "Démo", pre = { -2 } },
    [-4]  = { name = "[Démo] Rapport au capitaine",  level = 12, zone = "Zone de démo A", continent = "Démo", pre = { -2 } },
    [-5]  = { name = "[Démo] Le chef des bandits",   level = 14, minLevel = 12, zone = "Zone de démo A", continent = "Démo",
              elite = true, group = 3, pre = { -3, -4 }, npc = "Capitaine fictif" },
    [-6]  = { name = "[Démo] Chemin du nord",        level = 20, zone = "Zone de démo B", continent = "Démo" },
    [-7]  = { name = "[Démo] Chemin du sud",         level = 20, zone = "Zone de démo B", continent = "Démo" },
    [-8]  = { name = "[Démo] Le géant des collines", level = 24, minLevel = 21, zone = "Zone de démo B", continent = "Démo",
              elite = true, group = 5, preAny = { -6, -7 } },
    [-9]  = { name = "[Démo] La suite du géant",     level = 25, zone = "Zone de démo B", continent = "Démo",
              elite = true, group = 5, pre = { -8, -5 } },
}

-- Statut simulé de chaque quête en mode démo.
ns.DemoStatus = { [-1] = "done", [-2] = "done", [-3] = "done", [-4] = "log", [-6] = "done" }
ns.DemoLevel = 22
