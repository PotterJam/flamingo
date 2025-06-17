import { createSignal } from 'solid-js';
import { PrimaryButton } from './buttons/PrimaryButton';
import { useAppStore, actions } from '../store';
import { CreateRoomResponse } from '../api';
import { Logo } from './Logo';
import { OutlineButton } from './buttons/OutlineButton';

export const RoomConnection = () => {
    const [name, setName] = createSignal('');
    const [roomName, setRoomName] = createSignal('');
    const [roomNotFound, setRoomNotFound] = createSignal(false);

    const createRoom = async () => {
        const response = await fetch('/create-room', {
            method: 'POST',
            headers: { Accept: 'application/json' },
        });
        const room: CreateRoomResponse = await response.json();

        actions.nameChosen(name());
        actions.roomCreated(room.roomId);
    };

    const findRoom = async () => {
        const response = await fetch(`/${roomName()}`, {
            method: 'GET',
        });

        if (response.status == 200) {
            actions.nameChosen(name());
            setRoomNotFound(false);
            actions.joinRoom(roomName());
        }

        if (response.status == 404) {
            console.log('room not found');
            setRoomNotFound(true);
        }
    };

    return (
        <div class="mx-auto mt-10 flex w-full max-w-sm flex-col gap-6 rounded-lg bg-white p-6 text-center shadow-md">
            <Logo />
            <input
                type="text"
                value={name()}
                onInput={(e) => setName(e.target.value)}
                placeholder="Enter your name"
                maxLength={20}
                required
                class="w-full rounded border border-gray-300 p-2 transition duration-150 ease-in-out focus:ring-2 focus:ring-blue-500 focus:outline-none"
                aria-label="Enter your name"
            />
            <hr class="text-gray-300" />
            <div>
                {roomNotFound() && (
                    <p class="text-red-400">That room doesn't exist</p>
                )}
                <div class="flex flex-row gap-1">
                    <input
                        type="text"
                        placeholder="Room name"
                        value={roomName()}
                        onInput={(e) => {
                            setRoomName(e.target.value);
                            setRoomNotFound(false);
                        }}
                        aria-label="Enter room name to join"
                        class="w-full flex-1 rounded border border-gray-300 p-2 transition duration-150 ease-in-out focus:ring-2 focus:ring-blue-500 focus:outline-none"
                    />
                    <OutlineButton
                        disabled={!(roomName().trim() && name().trim())}
                        class="flex-0"
                        onClick={findRoom}
                    >
                        Join
                    </OutlineButton>
                </div>
                <h3 class="p-2 text-gray-500 italic">or</h3>
                <PrimaryButton disabled={!name().trim() || !!roomName().trim()} onClick={createRoom}>
                    Create room
                </PrimaryButton>
            </div>
        </div>
    );
};
