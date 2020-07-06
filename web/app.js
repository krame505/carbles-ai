const SECTOR_SIZE = 18
const NUM_PIECES = 4

const urlParams = new URLSearchParams(window.location.search)
const room = urlParams.get('room')
var started = false
var id = null
var playersInGame = []

function getColor(player) {
  return ['black', 'red', 'blue', 'green', 'orange', 'purple', 'brown', 'silver', 'gold', 'maroon', 'turquoise', 'indigo', 'midnightblue'][player]
}

function updateCell(cell, label, state, l, r, t, b, highlight=null) {
  cell.innerHTML = `
<div class="slot"
    <span class="label">${label}</span>
    <span class="marble" style="color: ${state.board[label] != null && state.board[label] != highlight? getColor(state.board[label]) : "white"}">
      ${state.board[label] != null && state.board[label] == highlight? '◯' : '⬤'}
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

  if (state.board[label] != null) {
    cell.style.color = getColor(state.board[label])
  }
}

function updateBoard(state) {
  // Clear board
  while (board.rows.length) {
    board.deleteRow(0)
  }
  for (i = 0; i < 8; i++) {
    board.insertRow()
  }

  // Fill in board
  let rows = board.rows
  for (p = 0; p < state.numPlayers; p++) {
    let prevP = (p + state.numPlayers - 1) % state.numPlayers

    let home = rows[7].insertCell(0);
    updateCell(home, prevP * SECTOR_SIZE, state, false, true, true, false, prevP)
    for (i = 1; i < 8; i++) {
      updateCell(rows[7 - i].insertCell(0), i + prevP * SECTOR_SIZE, state, false, false, i < 7, true)
    }
    for (i = 0; i < 7; i++) {
      updateCell(rows[i + 1].insertCell(0), i + 8 + prevP * SECTOR_SIZE, state, i == 6, false, true, i < 6)
    }
    rows[0].cells[0].colSpan = 2
    for (i = 0; i < 7; i++) {
      rows[i].insertCell(0)
    }
    updateCell(rows[7].insertCell(0), 15 + prevP * SECTOR_SIZE, state, true, true, false, false)
    rows[0].insertCell(0)
    let lot = rows[1].insertCell(0)
    lot.className = 'lotCell'
    lot.style.backgroundColor = getColor(p)
    let lotCount = state.lot[p]
    if (lotCount == 0) {
      lot.innerHTML = '⬤⬤<br>⬤⬤'
    } else if (lotCount == 1) {
      lot.innerHTML = '⬤⬤<br>⬤◯'
    } else if (lotCount == 2) {
      lot.innerHTML = '⬤⬤<br>◯◯'
    } else if (lotCount == 3) {
      lot.innerHTML = '⬤◯<br>◯◯'
    } else {
      lot.innerHTML = '◯◯<br>◯◯'
    }
    rows[2].insertCell(0)
    for (i = 0; i < NUM_PIECES; i++) {
      let cell = rows[6 - i].insertCell(0)
      updateCell(cell, "F" + p + i, state, false, false, i < NUM_PIECES - 1, true, p)
    }
    updateCell(rows[7].insertCell(0), 16 + prevP * SECTOR_SIZE, state, true, true, true, false)
    for (i = 0; i < 7; i++) {
      rows[i].insertCell(0)
    }
    updateCell(rows[7].insertCell(0), 17 + prevP * SECTOR_SIZE, state, true, true, false, false)
  }

  // Fill in header
  board.deleteTHead()
  let head = board.createTHead()
  for (p = state.numPlayers - 1; p >= 0; p--) {
    let headCell = document.createElement('th')
    headCell.innerHTML = playersInGame[p]
    headCell.colSpan = 3
    head.append(headCell)
    let spaceCell = document.createElement('th')
    spaceCell.colSpan = 2
    head.append(spaceCell)
  }
}

function reloadState() {
  console.log('Reloading state')
  $.ajax({url: "state.json?room=" + room}).done(
    function (s) {
      console.log("Got state: " + s)
      state = JSON.parse(s)
      playersInGame = state.playersInGame
      started = state.turn != null
      if (started) {
        turn.innerHTML = `${playersInGame[state.turn]}'s turn`
        hand.innerHTML = "Current hand: " + state.hand
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
          playersInRoom.innerHTML += p + "   "
        })
      aiPlayers.value = state.aiPlayers
      randomPlayers.value = state.randomPlayers
      actions.innerHTML = ""
      state.actions.forEach(
	function (a, i) {
	  actions.innerHTML +=
	    `<li><a href="#" ping="action?room=${room}&action=${i}">${a}</a></li>`
	})
      updateBoard(state.board)
    })
}

function addMessage(msg) {
  messages.innerHTML += msg + '<br>'
  messages.scrollTop = messages.scrollHeight
}

function connect() {
  const ws = new WebSocket("ws://" + location.host) // Only used to listen
  ws.onmessage = function (event) {
    console.log("Got message: " + event.data)
    msg = JSON.parse(event.data)
    if (msg.room == room) {
      if (msg.content) {
        addMessage(msg.content)
      }
      reloadState()
    }
  }
  ws.onclose = function(e) {
    console.log('Socket is closed. Reconnect will be attempted in 1 second.', e.reason)
    setTimeout(connect, 1000)
  }
}

function init() {
  connect()
  $.ajax({url: "register?room=" + room})
  $(window).bind('beforeunload', function() {
    $.ajax({url: "unregister?room=" + room})
  })
  reloadState()
}

function updateAutoPlayers() {
  $.ajax({url: `autoplayers?room=${room}&ai=${aiPlayers.value}&random=${randomPlayers.value}`})
}

function handleStartEndGame() {
  if (started) {
    if (confirm("Really end the game?")) {
      $.ajax({url: "end?room=" + room})
    }
  } else {
    $.ajax({url: "start?room=" + room})
  }
}
