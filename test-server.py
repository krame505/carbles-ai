#!/usr/bin/env python3

import json, random, string, websocket, http.client, sys, time, lorem

rooms = [str(i) for i in range(20)]
users = [''.join(random.choice(string.ascii_letters + string.digits) for k in range(10)) for i in range(20)]

sockets = {room: {} for room in rooms}
def socketSend(room, user, msg):
    # TODO: handle unicode escapes in JSON implementation
    sockets[room][user].send(json.dumps(msg, ensure_ascii=False))

labels = "🍏,🍎,🍐,🍊,🍋,🍌,🍉,🍇,🍓,🍈,🍒,🍑,🍍,🥝,🥑,🍅,🍆,🥒,🥕,🌽,🌶,🥔,🍠,🌰,🥜,🍯,🥐,🍞,🥖,🧀,🥚,🍳,🥓,🥞,🍤,🍗,🍖,🍕,🌭,🍔,🍟,🥙,🌮,🌯,🥗,🥘,🍝,🍜,🍲,🍥,🍣,🍱,🍛,🍚,🍙,🍘,🍢,🍡,🍧,🍨,🍦,🍰,🎂,🍮,🍭,🍬,🍫,🍿,🍩,🍪,🥛,🍼,☕️,🍵,🍶,🍺,🍻,🥂,🍷,🥃,🍸,🍹,🍾,🥄,🍴,🍽,⚽️,🏀,🏈,⚾️,🎾,🏐,🏉,🎱,🏓,🏸,🥅,🏒,🏑,🏏,⛳️,🏹,🎣,🥊,🥋,⛸,🎿,⛷,🏂,🏋️‍♀️,🏋️,🤺,🤼‍♀️,🤼‍♂️,🤸‍♀️,🤸‍♂️,⛹️‍♀️,⛹️,🤾‍♀️,🤾‍♂️,🏌️‍♀️,🏌️,🏄‍♀️,🏄,🏊‍♀️,🏊,🤽‍♀️,🤽‍♂️,🚣‍♀️,🚣,🏇,🚴‍♀️,🚴,🚵‍♀️,🚵,🎽,🏅,🎖,🥇,🥈,🥉,🏆,🏵,🎗,🎫,🎟,🎪,🤹‍♀️,🤹‍♂️,🎭,🎨,🎬,🎤,🎧,🎼,🎹,🥁,🎷,🎺,🎸,🎻,🎲,🎯,🎳,🎮,🎰".split(",")

host = 'localhost:8000' if len(sys.argv) < 2 else sys.argv[1]

def join(room, user):
    print("Joining", room, "with", user)
    ws = websocket.create_connection("ws://{}/websocket".format(host))
    sockets[room][user] = ws

    msg = {"type": "register", "room": room, "id": user, "name": user}
    ws.send(json.dumps(msg))

def leave(room, user):
    print("Quitting", room, "with", user)
    sockets[room][user].close()
    del sockets[room][user]

def get_state(room, user):
    print("Getting state for", room, "with", user)
    status = -1
    while status != 200:
        connection = http.client.HTTPConnection(host)
        connection.request('GET', "/state.json?room={room}&id={user}".format(room=room, user=user))
        response = connection.getresponse()
        status = response.status
        if status != 200:
            print("Error getting state:", status)
            time.sleep(0.1)
    content = response.read().decode()
    return json.loads(content)

def set_config(room, user, **config):
    print("Setting config for", room, ":", config)
    socketSend(room, user, {"type": "config", **config})

def start(room, user):
    print("Starting", room)
    socketSend(room, user, {"type": "start"})

def end(room, user):
    print("Ending", room)
    socketSend(room, user, {"type": "end"})

def chat(room, user):
    print("Chat in", room, "for", user)
    socketSend(room, user, {"type": "chat", "content": lorem.sentence()})

def label(room, user):
    label = random.choice(labels)
    print("Label in", room, "for", user, ":", label)
    socketSend(room, user, {"type": "label", "label": label})

def action(room, user, i):
    print("Action", i, "in", room, "for", user)
    socketSend(room, user, {"type": "action", "action": i})

def test(timeout=None):
    startTime = time.time()
    while timeout is None or time.time() < startTime + timeout:
        time.sleep(0.01)
        room = random.choice(rooms)
        if len(sockets[room]) == 0:
            join(room, random.choice(users))
        user = random.choice(list(sockets[room].keys()))
        state = get_state(room, user)
        actions = [
            lambda: set_config(room, user, aiPlayers=min(state['aiPlayers'] + 1, 4)),
            lambda: set_config(room, user, aiPlayers=state['aiPlayers'] - 1),
            lambda: set_config(room, user, randomPlayers=min(state['randomPlayers'] + 1, 4)),
            lambda: set_config(room, user, randomPlayers=state['randomPlayers'] - 1),
            lambda: set_config(room, user, partners=not state['partners']),
            lambda: set_config(room, user, openHands=not state['openHands']),
            lambda: set_config(room, user, aiTime=min(state['aiTime'] + 1, 5)),
            lambda: set_config(room, user, aiTime=state['aiTime'] - 1),
            lambda: chat(room, user),
            lambda: label(room, user),
        ]
        for u in users:
            if u in sockets[room]:
                if random.random() < 0.5:
                    actions.append(lambda u=u: leave(room, u))
            else:
                if random.random() < 0.1:
                    actions.append(lambda u=u: join(room, u))
        if 'turn' in state:
            if random.random() < 0.001:
                actions.append(lambda: end(room, user))
            turnUser = state['playersInGame'][state['turn']]
            if not turnUser.startswith('AI') and not turnUser.startswith('Random'):
                turnUser = turnUser[len(turnUser) - 10:]  # Strip the label
                if turnUser not in users:
                    # Game has a player that is not included by the test script, possibly from a previous run: end the game
                    end(room, user)
                    continue
                elif turnUser not in sockets[room]:
                    # User isn't currently in the room: rejoin
                    join(room, turnUser)
                turnUserState = get_state(room, turnUser)
                moves = [lambda: action(room, turnUser, i) for i in range(0, len(turnUserState['actions']))]
                actions.extend(moves * 2)
        else:
            actions.append(lambda: start(room, user))
        random.choice(actions)()

if __name__ == '__main__':
    print("Testing on", host)
    timeout = float(sys.argv[2]) if len(sys.argv) >= 3 else None
    test(timeout)
