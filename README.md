# Solutions Damn Vulnerable DeFi v4

TD Sécurité - Cours Monnaies Numériques 2026  
Par Sacha (zag2110)

## Description

Repo de mes solutions pour les challenges Damn Vulnerable DeFi. C'est un CTF de sécurité smart contracts avec 18 challenges qui couvrent pas mal de vulnérabilités classiques en DeFi (flash loans, réentrance, manipulation d'oracles, etc).

Le but c'est d'exploiter les failles dans les contrats pour récupérer/drainer des fonds ou compromettre le système. Tout est fait avec Foundry.

**✅ Progression actuelle : 18/18 (100%) - TOUS LES CHALLENGES RÉSOLUS !**

## Challenges résolus

| # | Challenge | Vulnérabilité exploitée | Difficulté | Notes |
|---|-----------|------------------------|------------|-------|
| 01 | Unstoppable | DOS par déséquilibre du vault | ⭐ | Facile - juste envoyer des tokens direct |
| 02 | Naive Receiver | Multicall + Forwarder abuse | ⭐⭐ | Utiliser multicall + EIP-2771 pour vider |
| 03 | Truster | Flash loan + approve() | ⭐ | Approuver puis transférer pendant le flash loan |
| 04 | Side Entrance | Réentrance classique | ⭐ | Deposit pendant le flashloan |
| 05 | The Rewarder | Flash loan + snapshot timing | ⭐⭐ | Emprunter avant le snapshot de rewards |
| 06 | Selfie | Gouvernance takeover | ⭐⭐ | Snapshot du voting power avec flash loan |
| 07 | Compromised | Oracle manipulation + crypto leak | ⭐⭐⭐ | Décoder les clés depuis base64 dans les logs |
| 08 | Puppet | Manipulation prix Uniswap V1 | ⭐⭐ | Dump massif pour changer le prix spot |
| 09 | Puppet V2 | Manipulation prix Uniswap V2 | ⭐⭐ | Même principe avec WETH/DVT pool |
| 10 | Puppet V3 | Manipulation prix Uniswap V3 | ⭐⭐⭐ | Exploiter TWAP oracle avec gros swap |
| 11 | Free Rider | Bug dans le marketplace NFT | ⭐⭐ | Acheter tous les NFTs avec l'ETH d'un seul |
| 12 | Backdoor | Safe wallet + delegatecall | ⭐⭐⭐ | Exploit via le callback à l'init du wallet |
| 13 | Climber | Timelock bypass | ⭐⭐⭐⭐ | Exploiter l'ordre execute() avant schedule() |
| 14 | Wallet Mining | CREATE2 salt mining | ⭐⭐⭐ | Bruteforce le salt pour avoir la bonne adresse |
| 15 | ABI Smuggling | Manipulation encodage bas niveau | ⭐⭐⭐⭐ | Smuggling via padding + offset manipulation |
| 16 | Withdrawal | Bridge L1/L2 vulnerability | ⭐⭐⭐⭐ | Exploiter message replay dans le bridge |
| 17 | Curvy Puppet | Curve oracle manipulation | ⭐⭐⭐ | Manipuler le prix via Curve pool |
| 18 | Shards | NFT marketplace rounding error | ⭐⭐⭐ | Exploiter les arrondis dans le marketplace |

## Installation & Usage

```bash
git clone https://github.com/zag2110/TD-Security.git
cd TD-Security

# Config
cp .env.sample .env
# Mettre votre URL RPC Alchemy dans .env si besoin (pour les tests mainnet fork)

# Installation
forge install

# Compilation
forge build

# Lancer tous les tests
forge test

# Lancer un test spécifique
forge test --match-test test_unstoppable -vv

# Avec traces complètes (utile pour debug)
forge test --match-test test_puppet -vvvv

# Lancer juste un fichier de challenge
forge test --match-path test/unstoppable/Unstoppable.t.sol
```

## Notes techniques

**Framework** : Foundry (forge/cast/anvil)

**Versions** :
- Solidity 0.8.25
- Foundry latest

**Techniques utilisées** :
- Flash loans pour les attaques one-shot
- vm.warp / vm.prank / vm.sign pour les cheatcodes Foundry
- Forking mainnet quand nécessaire (Uniswap, Curve)
- Création de contrats attaquants custom (inline dans les tests ou séparés)
- Exploitation de réentrance et race conditions
- Manipulation d'oracles DEX (prix spot vs TWAP)
- Mining d'adresses avec CREATE2
- EIP-2771 (meta-transactions) pour naive-receiver
- Manipulation d'ABI encoding pour ABI smuggling
- Exploitation de bridges L1/L2

**Méthodologie** :
1. Lire le code des contrats vulnérables
2. Identifier les invariants qui peuvent être cassés
3. Coder l'exploit dans le fichier de test (section "CODE YOUR SOLUTION HERE")
4. Valider que ça passe avec `forge test`
5. Documenter l'exploit avec des commentaires en français

**Règles respectées** :
- Toujours utiliser le compte `player`
- Ne pas modifier setup() ni _isSolved()
- Une seule transaction quand c'est spécifié (check avec vm.getNonce)
- Possibilité de déployer des contrats attaquants custom

## Structure

```
.
├── src/                          # Contrats vulnérables (NE PAS MODIFIER)
│   ├── unstoppable/             # Challenge 1
│   ├── naive-receiver/          # Challenge 2
│   └── ...                      # Etc.
├── test/                        # Mes solutions (les fichiers .t.sol)
│   ├── unstoppable/
│   │   └── Unstoppable.t.sol   # Test + exploit
│   └── ...
└── lib/                         # Dependencies (OpenZeppelin, Uniswap, etc.)
```

## Détails des exploits

### 🎯 Top 3 des challenges les plus intéressants

1. **ABI Smuggling** - Manipulation bas niveau de l'encoding ABI pour bypasser les checks. Super technique.

2. **Climber** - Exploiter la logique du timelock qui vérifie la schedule APRÈS l'execution. Faut réussir à faire un call qui se schedule lui-même.

3. **Wallet Mining** - Bruteforce un salt pour que l'adresse déployée via CREATE2 corresponde à une adresse autorisée. Faut miner jusqu'à trouver le bon.

### 💡 Leçons apprises

- **Ne jamais faire confiance au prix spot** d'un DEX - toujours utiliser TWAP ou oracle externe
- **Vérifier l'ordre des opérations** dans les timelocks et gouvernances
- **Attention aux réentrances** même quand il n'y a pas de payable
- **Les flash loans** sont l'arme ultime pour manipuler les snapshots/votes
- **CREATE2 est prévisible** - attention aux whitelists basées sur les adresses
- **Les meta-transactions** (EIP-2771) peuvent être abusées si mal implémentées
- **L'encodage ABI** peut être manipulé pour bypasser les validations

## Remarques

Tous les contrats ici sont **VOLONTAIREMENT vulnérables**. C'est pour apprendre.

**⚠️ NE PAS utiliser ce code en prod évidemment. ⚠️**

Les exploits sont commentés en français pour mieux expliquer la logique.

---

## Résultats des tests

```bash
$ forge test
[PASS] 18 test suites | 36 tests passed | 0 failed
```

Tous les challenges sont résolus ! 🎉

---

## Crédits

Projet original : [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) par The Red Guild  
Solutions et adaptations : Sacha (zag2110)  
Cours Sécurité & Monnaies Numériques - 2026
