import { useTimer } from '../hooks/useTimer';

function TimerDisplay(props: { endTime: number }) {
    const remainingSeconds = useTimer(() => props.endTime);

    return <p class="text-xl font-bold text-white">{remainingSeconds()}</p>;
}

export default TimerDisplay;
