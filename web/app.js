const SECTOR_SIZE = 18
const NUM_PIECES = 4

function getColor(player) {
  return ['black', 'red', 'blue', 'green', 'orange', 'purple', 'brown', 'silver', 'gold', 'maroon', 'turquoise', 'mauve', 'scarlet'][player]
}

function updateCell(cell, label, state, highlight=null) {
  cell.style.border = '1px solid black'
  cell.innerHTML = `
<div class="slot"
    <span class="label">${label}</span>
    <span class="marble" style="color: ${state.board[label] != null && state.board[label] != highlight? getColor(state.board[label]) : "white"}">
      ${state.board[label] != null && state.board[label] == highlight? '◯' : '⬤'}
    </span>
</div>`
  cell.className = "slotCell"
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

    let home = rows[7].insertCell(0)
    updateCell(home, prevP * SECTOR_SIZE, state, prevP)
    for (i = 1; i < 8; i++) {
      updateCell(rows[7 - i].insertCell(0), i + prevP * SECTOR_SIZE, state)
    }
    for (i = 0; i < 7; i++) {
      updateCell(rows[i + 1].insertCell(0), i + 8 + prevP * SECTOR_SIZE, state)
    }
    rows[0].cells[0].colSpan = 2
    for (i = 0; i < 7; i++) {
      rows[i].insertCell(0)
    }
    updateCell(rows[7].insertCell(0), 15 + prevP * SECTOR_SIZE, state)
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
      updateCell(cell, "F" + p + i, state, p)
    }
    updateCell(rows[7].insertCell(0), 16 + prevP * SECTOR_SIZE, state)
    for (i = 0; i < 7; i++) {
      rows[i].insertCell(0)
    }
    updateCell(rows[7].insertCell(0), 17 + prevP * SECTOR_SIZE, state)
  }

  // Fill in header
  board.deleteTHead()
  let head = board.createTHead()
  for (p = state.numPlayers - 1; p >= 0; p--) {
    let headCell = document.createElement('th')
    headCell.innerHTML = "Player " + p
    headCell.colSpan = 3
    head.append(headCell)
    let spaceCell = document.createElement('th')
    spaceCell.colSpan = 2
    head.append(spaceCell)
  }
}

function reloadState() {
  let urlParams = new URLSearchParams(window.location.search)
  let player = urlParams.get('player')
  $.ajax({url: "state.json"}).done(
      function (s) {
	state = JSON.parse(s)
	updateBoard(state)
	turn.innerHTML = `Player ${state.turn}'s turn`
	turn.style.color = getColor(state.turn)
      })
  if (player != null) {
    $.ajax({url: "player_state.json?player=" + player}).done(
	function (s) {
	  state = JSON.parse(s)
	  hand.innerHTML = "Current hand: " + state.hand
	  actions.innerHTML = ""
	  state.actions.forEach(
	      function (a, i) {
		actions.innerHTML +=
		    `<li><a href="#" ping="action?player=${player}&action=${i}">${a}</a></li>`
	      })
	})
  }
}

function addMessage(msg) {
  messages.innerHTML += msg + '<br>'
  messages.scrollTop = messages.scrollHeight
}

function connect() {
  const ws = new WebSocket("ws://" + location.host) // Only used to listen
  ws.onmessage = function (event) {
    if (event.data) {
      addMessage(event.data)
    }
    reloadState()
  }
  ws.onclose = function(e) {
    console.log('Socket is closed. Reconnect will be attempted in 1 second.', e.reason)
    setTimeout(connect, 1000)
  }
}

function init() {
  connect()
  reloadState()
}
