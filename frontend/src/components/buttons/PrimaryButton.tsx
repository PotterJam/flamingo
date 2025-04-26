import { FC } from 'react';

interface PrimaryButtonProps {
    onClick: React.MouseEventHandler<HTMLButtonElement>;
    disabled?: boolean;
    children: React.ReactNode;
}

export const PrimaryButton: FC<PrimaryButtonProps> = ({
    onClick,
    disabled = false,
    children,
}) => {
    const enabledStyles =
        'w-full rounded bg-pink-400 px-4 py-2 font-bold text-white hover:bg-pink-500';
    const disabledStyles =
        'w-full rounded bg-gray-300 px-4 py-2 font-bold text-gray-400';
    return (
        <button
            onClick={onClick}
            disabled={disabled}
            className={disabled ? disabledStyles : enabledStyles}
        >
            {children}
        </button>
    );
};
