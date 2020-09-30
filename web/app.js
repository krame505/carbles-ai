const SECTOR_SIZE = 18
const NUM_PIECES = 4

const urlParams = new URLSearchParams(window.location.search)

function getRoom() {
  var result = urlParams.get('room')
  if (!result) {
    result = Math.random().toString(36).substring(3)
  }
  if (result.length >= 30) {
    result = result.substring(0, 29)
  }
  return result
}

function getName() {
  var result = urlParams.get('name')
  while (!result) {
    result = prompt("Please enter your name", "")
  }
  return result
}

const room = getRoom()
const name = getName()

const idCookie = document.cookie.split('; ').find(row => row.startsWith('id'))
const id = idCookie? idCookie.split('=')[1] : Math.random().toString(36).substring(3)
if (!idCookie) {
  document.cookie = `id=${id}; expires=Fri, 31 Dec 9999 23:59:59 GMT`
}

var started = false
var playersInGame = []

var ws = null

function partner(numPlayers, p) {
  return (p + Math.floor(numPlayers / 2)) % numPlayers
}

function getColor(player) {
  return ['#505050', 'red', 'blue', 'green', 'orange', 'purple', 'gold', 'brown', 'turquoise', 'olive', 'coral', 'goldenrod'][player]
}

function updateCell(cell, label, state, playerLabels, l, r, t, b, highlight=null) {
  let cellId = state.board[label]
  cell.innerHTML = `
<div class="slot"
    <span class="label">${label}</span>
    <span class="marble" style="color: ${cellId != null && cellId != highlight? getColor(cellId) : "white"}">
      ${cellId != null && playerLabels[cellId]? playerLabels[cellId] : cellId != null && cellId == highlight? '◯' : '⬤'}
    </span>
</div>`
  cell.className = "slotCell"

  if (l) cell.style.borderLeft = '0px'
  if (r) cell.style.borderRight = '0px'
  if (t) cell.style.borderTop = '0px'
  if (b) cell.style.borderBottom = '0px'

  if (highlight != null) {
    cell.style.backgroundColor = getColor(highlight)
  }

  if (cellId != null) {
    cell.style.color = getColor(cellId)
  }
}

function updateBoard(state, playerLabels) {
  // Clear board
  while (board.rows.length) {
    board.deleteRow(0)
  }
  for (i = 0; i < 8; i++) {
    board.insertRow()
  }

  // Fill in board
  let rows = board.rows
  for (i = 1; i < 8; i++) {
    rows[i].insertCell(0)
  }
  rows[1].cells[0].innerHTML = '<b>⋮</b>'

  for (p = 0; p < state.numPlayers; p++) {
    let prevP = (p + state.numPlayers - 1) % state.numPlayers

    for (i = 0; i < 8; i++) {
      updateCell(rows[i].insertCell(0), i + 7 + prevP * SECTOR_SIZE, state, playerLabels, i == 7, false, i > 0, i < 7)
    }
    rows[0].cells[0].colSpan = 2
    for (i = 0; i < 7; i++) {
      rows[i].insertCell(0)
    }
    updateCell(rows[7].insertCell(0), 15 + prevP * SECTOR_SIZE, state, playerLabels, true, true, false, false)
    rows[0].insertCell(0)
    let lot = rows[1].insertCell(0)
    lot.className = 'lotCell'
    lot.style.backgroundColor = getColor(p)
    let lotCount = state.lot[p]
    let pl = playerLabels[p]? playerLabels[p] : '◯'
    if (lotCount == 0) {
      lot.innerHTML = '⬤⬤<br>⬤⬤'
    } else if (lotCount == 1) {
      lot.innerHTML = `⬤⬤<br>⬤${pl}`
    } else if (lotCount == 2) {
      lot.innerHTML = `⬤⬤<br>${pl}${pl}`
    } else if (lotCount == 3) {
      lot.innerHTML = `⬤${pl}<br>${pl}${pl}`
    } else {
      lot.innerHTML = `${pl}${pl}<br>${pl}${pl}`
    }
    rows[2].insertCell(0)
    for (i = 0; i < NUM_PIECES; i++) {
      let cell = rows[6 - i].insertCell(0)
      updateCell(cell, "F" + p + i, state, playerLabels, false, false, i < NUM_PIECES - 1, true, p)
    }
    updateCell(rows[7].insertCell(0), 16 + prevP * SECTOR_SIZE, state, playerLabels, true, true, true, false)
    for (i = 0; i < 7; i++) {
      rows[i].insertCell(0)
    }
    updateCell(rows[7].insertCell(0), 17 + prevP * SECTOR_SIZE, state, playerLabels, true, true, false, false)
    updateCell(rows[7].insertCell(0), p * SECTOR_SIZE, state, playerLabels, false, true, true, false, p)
    for (i = 1; i < 7; i++) {
      updateCell(rows[7 - i].insertCell(0), i + p * SECTOR_SIZE, state, playerLabels, false, false, i < 7, true)
    }
  }
  rows[0].insertCell(0)
  rows[0].cells[0].innerHTML = '<b>⋮</b>'

  // Fill in header
  board.deleteTHead()
  let head = board.createTHead()
  for (p = state.numPlayers - 1; p >= 0; p--) {
    head.append(document.createElement('th'))
    let headCell = document.createElement('th')
    headCell.innerHTML = `<span style="color: ${getColor(p)};">${playersInGame[p]}</span>`
    if (state.partners) {
      p2 = partner(state.numPlayers, p)
      headCell.innerHTML += `<br>(<span style="color: ${getColor(p2)};">${playersInGame[p2]}</span>)`
    }
    headCell.colSpan = 3
    head.append(headCell)
    head.append(document.createElement('th'))
  }
}

var reloadPending = false
function reloadState() {
  // Synchronization is done on the server side, so if a second event occurs
  // the original state request will still return the most recent state.
  if (reloadPending) {
    console.log("Reload is pending")
  } else {
    reloadPending = true
    console.log("Reloading state")
    $.ajax({url: `state.json?room=${room}&id=${id}`, cache: false, timeout: 3000}).done(
	function (s) {
	  reloadPending = false
	  state = JSON.parse(s)
	  console.log("Got state", state)
	  playersInGame = state.playersInGame
	  started = state.turn != null
	  if (started) {
            turn.innerHTML = `${playersInGame[state.turn]}'s turn`
	    if ('hand' in state) {
              hand.innerHTML = "Current hand: " + state.hand
	    } else {
              hand.innerHTML = ""
	    }
	    if ('hands' in state) {
	      for (p = 0; p < state.board.numPlayers; p++) {
		if (p != state.id) {
		  hand.innerHTML += `<br><span style="color: ${getColor(p)};">${playersInGame[p]}</span>'s hand: ` + state.hands[p]
		}
	      }
	    }
            turn.style.color = getColor(state.turn)
            startEndGame.innerHTML = "End Game"
	  } else {
            turn.innerHTML = ""
            hand.innerHTML = ""
            startEndGame.innerHTML = "Start Game"
	  }
	  playersInRoom.innerHTML = ""
	  state.playersInRoom.forEach(
              function (p, i) {
		playersInRoom.innerHTML += (i? ",  " : "") + p
              })
	  aiPlayers.value = state.aiPlayers
	  randomPlayers.value = state.randomPlayers
	  partners.checked = state.partners
	  openHands.checked = state.openHands
	  actions.innerHTML = ""
	  state.actions.forEach(
	      function (a, i) {
		actions.innerHTML +=
		    `<li><a href="javascript:void(0);" onclick="sendAction(${i})" class="action">${a}</a></li>`
	      })
	  updateBoard(state.board, state.playerLabels)
	}).fail(function () {
	  reloadPending = false
	  console.log("Failed to reload state")
	})
  }
}

function addMessage(id, name, chat, msg) {
  messagesOut.innerHTML +=`
<span style="${id != null? `color:${getColor(id)}` : ""}">
  <b>${name? name + ": " : ""}</b>
  <span style="${chat? "" : "font-style:italic;"}${id != null? "" : "font-weight:bold;"}">
    ${msg}
  </span>
</span><br>`
  messagesOut.scrollTop = messagesOut.scrollHeight
}

var reconnectInterval = 1
function connect() {
  console.log("Connecting")
  if (ws != null && ws.readyState != WebSocket.OPEN) {
    ws.close()
  }
  ws = new WebSocket((location.protocol === "https:"? "wss://" : "ws://") + location.host)
  ws.onmessage = function (event) {
    msg = JSON.parse(event.data)
    console.log("Got message", msg)
    if (msg.disconnect) {
      addMessage(null, null, false, "Room joined in another tab!  Disconnected here; refresh the page if you would like to reconnect.")
      actions.innerHTML = ""
    } else if (msg.room == room) {
      if (msg.content) {
	addMessage(msg.id, msg.name, msg.chat, msg.content)
      }
      if (msg.reload) {
	reloadState()
      }
    }
  }
  ws.onopen = function(e) {
    console.log("Joining room")
    ws.send(`join:${room}:${id}:${name}`)
    reconnectInterval = 1
  }
  ws.onclose = function(e) {
    console.log(`Socket is closed. Reconnect will be attempted in ${reconnectInterval} seconds.`, e.reason)
    addMessage(null, null, false, `Connection lost!  Reconnecting in ${reconnectInterval} seconds.`)
    setTimeout(connect, reconnectInterval * 1000)
    if (reconnectInterval < 10) {
      reconnectInterval += 1
    }
  }
  ws.onerror = function(e) {
    console.log('Websocket error: ', e)
  }
}

function disconnect() {
  console.log("Disconnecting")
  ws.close()
}

function initLink() {
  let url = new URL(window.location)
  joinLink.value = `${url.origin}${url.pathname}?room=${room}`
}

function copyLink() {
  joinLink.select()
  joinLink.setSelectionRange(0, 99999) // For mobile devices
  document.execCommand("copy");
}

function updateConfig() {
  $.ajax({url: `config?room=${room}&ai=${aiPlayers.value}&random=${randomPlayers.value}&partners=${partners.checked}&openhands=${openHands.checked}`, cache: false})
}

function handleStartEndGame() {
  if (started) {
    if (confirm("Really end the game?  This will end the game for all players.")) {
      $.ajax({url: "end?room=" + room, cache: false})
    }
  } else {
    $.ajax({url: "start?room=" + room, cache: false})
  }
}

function handleChat() {
  if (event.type == 'click' || (event.type == 'keydown' && event.key == 'Enter')) {
    sendChat(chatInput.value)
    chatInput.value = ""
  }
}

function sendAction(i) {
  console.log("Sending action", i)
  ws.send(`action:${i}`)
}

function sendChat(msg) {
  ws.send(`chat:${msg}`)
}

function updateLabel(e) {
  console.log("Setting label to", e)
  ws.send(`label:${e}`)
}
