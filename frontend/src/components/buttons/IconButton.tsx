import React from 'react';
import { Icon, IconName, IconSize } from '../Icon';

export interface IconButtonProps {
    name: IconName;
    size?: IconSize;
    alt?: string;
    className?: string;
    onClick: () => void;
    disabled?: boolean;
}

export const IconButton: React.FC<IconButtonProps> = ({
    name,
    size = 'm',
    alt,
    className = '',
    onClick,
    disabled = false,
}) => {
    return (
        <button
            type="button"
            onClick={onClick}
            disabled={disabled}
            className={`mx-auto scale-100 transform rounded-full border-none bg-transparent p-0 grayscale transition-all duration-300 ease-in-out outline-none hover:scale-120 hover:drop-shadow-lg hover:grayscale-0 disabled:cursor-not-allowed disabled:opacity-50 disabled:hover:scale-100 disabled:hover:grayscale ${disabled ? '' : 'cursor-pointer'} ${className} `}
        >
            <Icon
                name={name}
                size={size}
                alt={alt}
                className="icon-button-icon"
            />
        </button>
    );
};
