# Damn Vulnerable DeFi v4 - Solutions

TD Sécurité - Cours Monnaies Numériques 2026  
Par Sacha (zag2110)

## Description

Mes solutions pour les challenges Damn Vulnerable DeFi. CTF de sécurité smart contracts avec 18 challenges qui couvrent les vulnérabilités classiques en DeFi (flash loans, réentrance, manipulation d'oracles, etc).

Le but: exploiter les failles dans les contrats pour récupérer/drainer des fonds. Framework utilisé: Foundry.

**Progression: 18/18 challenges résolus**

## Liste des challenges

| Challenge | Vulnérabilité | Notes |
|-----------|---------------|-------|
| Unstoppable | DOS par déséquilibre du vault | Simple - envoyer des tokens sans mint |
| Naive Receiver | Multicall + Forwarder abuse | Combiner multicall avec EIP-2771 |
| Truster | Flash loan + approve() | Approuver pendant le flash loan |
| Side Entrance | Réentrance | Deposit pendant le flashloan |
| The Rewarder | Flash loan + snapshot timing | Emprunter avant snapshot |
| Selfie | Gouvernance takeover | Voter avec les tokens empruntés |
| Compromised | Oracle manipulation + leak | Clés privées dans les logs HTTP (base64) |
| Puppet | Prix Uniswap V1 | Dump pour manipuler le prix |
| Puppet V2 | Prix Uniswap V2 | Pareil avec WETH pool |
| Puppet V3 | Prix Uniswap V3 | TWAP manipulation |
| Free Rider | Bug marketplace NFT | Acheter N NFTs avec le prix d'un |
| Backdoor | Safe wallet + delegatecall | Callback à l'init |
| Climber | Timelock bypass | Execute avant schedule |
| Wallet Mining | CREATE2 mining | Bruteforce le salt |
| ABI Smuggling | Encodage ABI | Offset manipulation |
| Withdrawal | Bridge L1/L2 | Message replay |
| Curvy Puppet | Curve oracle | Manipuler prix Curve |
| Shards | NFT marketplace | Rounding errors |

## Installation

```bash
git clone https://github.com/zag2110/TD-Security.git
cd TD-Security

# Setup
forge install
forge build

# Tests
forge test                                          # tous les tests
forge test --match-test test_unstoppable -vv       # un test spécifique
forge test --match-test test_puppet -vvvv          # avec traces
forge test --match-path test/unstoppable/*.t.sol   # un fichier
```

Note: Copier .env.sample vers .env si besoin (pour fork mainnet)

## Notes techniques

**Framework** : Foundry (forge/cast/anvil)

**Versions** :
- Solidity 0.8.25
- Foundry latest

**Techniques utilisées** :
- Flash loans pour les attaques one-shot
- vTechniques

Framework: Foundry (Solidity 0.8.25)

Techniques principales:
- Flash loans pour manipuler les états/snapshots
- Cheatcodes Foundry (vm.warp, vm.prank, vm.sign)
- Fork mainnet (Uniswap, Curve)
- Contrats attaquants custom
- Réentrance classique
- Manipulation d'oracles (prix spot vs TWAP)
- CREATE2 address mining
- Meta-transactions (EIP-2771)
- ABI encoding manipulation
- Bridge exploits

Méthodologie:
1. Lire le code vulnérable
2. Trouver l'invariant à casser
3. Coder l'exploit dans le test
4. Valider avec forge test

Règles:
- Toujours avec le compte player
- Pas toucher au setup() ni _isSolved()
- Respecter les limites de transactionschiers .t.sol)
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
- *Challenges intéressants

**ABI Smuggling**: Manipulation bas niveau de l'ABI encoding pour bypass les checks. Le plus technique.

**Climber**: Exploiter le fait que le timelock vérifie la schedule APRÈS l'execution. Faut faire un call qui se schedule lui-même.

**Wallet Mining**: Bruteforce un salt CREATE2 pour matcher une adresse autorisée.

## Ce qu'on apprend

- PNotes

Tous les contrats sont VOLONTAIREMENT vulnérables. C'est éducatif.

Ne pas utiliser ce code en prod (évidemment).

Les exploits sont commentés en français.

---

Résultats: 18/18 challenges résolus (36 tests passed)

---

Projet original: [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) par The Red Guild  
Solutions: Sacha (zag2110)  
Cours Sécurité & Monnaies Numériques