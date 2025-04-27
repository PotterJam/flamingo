import { FC, useState } from 'react';
import { PrimaryButton } from './buttons/PrimaryButton';
import { useAppStore } from '../store';
import { CreateRoomResponse } from '../api';
import { Logo } from './Logo';
import { OutlineButton } from './buttons/OutlineButton';

export const RoomConnection: FC = () => {
    const [name, setName] = useState('');
    const [roomName, setRoomName] = useState('');
    const [roomNotFound, setRoomNotFound] = useState(false);

    const roomCreated = useAppStore((s) => s.roomCreated);
    const joinRoom = useAppStore((s) => s.joinRoom);

    const createRoom = async () => {
        const response = await fetch('/create-room', {
            method: 'POST',
            headers: { Accept: 'application/json' },
        });
        const room: CreateRoomResponse = await response.json();

        roomCreated(room);
    };

    const findRoom = async () => {
        const response = await fetch(`/${roomName}`, {
            method: 'GET',
        });

        if (response.status == 200) {
            console.log('room found');
            setRoomNotFound(false);
            joinRoom(roomName);
        }

        if (response.status == 404) {
            console.log('room not found');
            setRoomNotFound(true);
        }
    };

    return (
        <div className="mx-auto mt-10 flex w-full max-w-sm flex-col gap-6 rounded-lg bg-white p-6 text-center shadow-md">
            <Logo />
            <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Enter your name"
                maxLength={20}
                required
                className="w-full rounded border border-gray-300 p-2 transition duration-150 ease-in-out focus:ring-2 focus:ring-blue-500 focus:outline-none"
                aria-label="Enter your name"
            />
            <hr className="text-gray-300" />
            <div>
                {roomNotFound && (
                    <p className="text-red-400">That room doesn't exist</p>
                )}
                <div className="flex flex-row gap-1">
                    <input
                        type="text"
                        placeholder="Room name"
                        value={roomName}
                        onChange={(e) => {
                            setRoomName(e.target.value);
                            setRoomNotFound(false);
                        }}
                        area-label="Enter room name to join"
                        className="w-full flex-1 rounded border border-gray-300 p-2 transition duration-150 ease-in-out focus:ring-2 focus:ring-blue-500 focus:outline-none"
                    />
                    <OutlineButton
                        disabled={!(roomName.trim() && name.trim())}
                        className="flex-0"
                        onClick={findRoom}
                    >
                        Join
                    </OutlineButton>
                </div>
                <h3 className="p-2 text-gray-500 italic">or</h3>
                <PrimaryButton disabled={!name.trim()} onClick={createRoom}>
                    Create room
                </PrimaryButton>
            </div>
        </div>
    );
};
