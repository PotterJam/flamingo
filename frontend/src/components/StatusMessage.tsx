function StatusMessage({ message = '' }) {
    return (
        <div className="min-h-[1.5rem] text-center text-base text-gray-700 transition-all duration-200 lg:text-lg">
            {message || '\u00A0'}
        </div>
    );
}

export default StatusMessage;
