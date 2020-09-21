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

## Self modifying text
```
<div id="laughs" onmouseover="function update() { laughs.innerHTML += ' ha'; setTimeout(update, 500) }; update();">ha ha ha ha ha ha ha</div>
```

## Youtube video
```
<iframe width="420" height="315" src="https://www.youtube.com/embed/tgbNymZ7vqY"></iframe>
```
