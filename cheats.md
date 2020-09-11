# Cheats
Type these in the chat to mess with people endlessly.

## Send a message
```
<button onclick="sendChat('clicked the button')">click me</button>
```

## Set label
```
<button onclick="updateLabel('🐵')">click me</button>
```

## Print hand
```
<button onclick="sendChat('my cards are ' + hand.innerHTML.split(':')[1])">click me</button>
```

## Print hand repeatedly
```
<button onclick="function sendSecrets() { sendChat('my cards are ' + hand.innerHTML.split(':')[1]); setTimeout(sendSecrets, 60000) }; sendSecrets()">click me</button>
```

## Print moves
```
<button onclick="sendChat('my moves are' + actions.innerHTML)">click me</button>
```
